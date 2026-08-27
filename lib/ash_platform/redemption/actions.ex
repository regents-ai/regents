defmodule AshPlatform.Redemption.Actions do
  @moduledoc false
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.Human
  alias AshPlatform.Redemption.ChainClient
  alias AshPlatform.WalletActions.{Abi, Address, Envelope, RedemptionAbi}

  @resource "animata_redemption"
  @actions ~w(approve_nft_collection approve_exact_usdc redeem claim)
  @risk %{
    "approve_nft_collection" =>
      "Allow the verified Animata redeemer to transfer NFTs from this collection.",
    "approve_exact_usdc" => "Approve exactly 80 USDC for the verified Animata redeemer.",
    "redeem" =>
      "Transfer the selected Animata NFT and exactly 80 USDC to start the REGENT stream.",
    "claim" => "Claim all REGENT currently unlocked from your redemption vest."
  }

  def overview(_input, _context), do: ChainClient.module().overview(nil, nil, nil)

  def account_for_wallet(input, %{actor: %Human{}} = context) do
    with {:ok, signer, _lease} <- current_wallet(input.arguments.expected_signer, context),
         {:ok, collection} <-
           optional_collection(input.arguments.collection, input.arguments.token_id),
         do: ChainClient.module().overview(signer, collection, input.arguments.token_id)
  end

  def account_for_wallet(_input, _context), do: {:error, :authentication_required}

  def prepare(action, input, %{actor: %Human{}} = context) do
    with {:ok, signer, lease} <- current_wallet(input.arguments.expected_signer, context),
         {:ok, envelope} <- prepare_action(action, input.arguments, signer) do
      return_current(lease, signer, envelope)
    end
  end

  def prepare(_, _, _), do: {:error, :authentication_required}

  defp prepare_action("approve_nft_collection", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection),
         {:ok, facts} <- ChainClient.module().overview(signer, collection, arguments[:token_id]),
         :nft_approval_required <- next_step(facts, signer) do
      redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())

      {:ok,
       Envelope.new(
         "approve_nft_collection",
         signer,
         RedemptionAbi.encode_erc721("set_approval_for_all", [redeemer, true]),
         resource: @resource,
         to: collection,
         contract_name: RedemptionAbi.collection_name(collection),
         risk_copy: @risk["approve_nft_collection"],
         arguments: %{collection: collection, operator: redeemer, approved: true}
       )}
    else
      step when is_atom(step) -> refusal(step)
      error -> error
    end
  end

  defp prepare_action("approve_exact_usdc", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection),
         {:ok, facts} <- ChainClient.module().overview(signer, collection, arguments.token_id),
         :exact_usdc_approval_required <- next_step(facts, signer) do
      redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())
      usdc = Abi.normalize_address!(RedemptionAbi.usdc_address())
      amount = String.to_integer(RedemptionAbi.price_atomic())

      {:ok,
       Envelope.new(
         "approve_exact_usdc",
         signer,
         RedemptionAbi.encode_erc20("approve", [redeemer, amount]),
         resource: @resource,
         to: usdc,
         contract_name: "USDC",
         risk_copy: @risk["approve_exact_usdc"],
         arguments: %{spender: redeemer, amount_atomic: Integer.to_string(amount), mode: "exact"}
       )}
    else
      step when is_atom(step) -> refusal(step)
      error -> error
    end
  end

  defp prepare_action("redeem", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection),
         :ok <- valid_token_id(arguments.token_id),
         {:ok, facts} <- ChainClient.module().overview(signer, collection, arguments.token_id),
         :ready <- next_step(facts, signer) do
      {:ok,
       Envelope.new(
         "redeem",
         signer,
         RedemptionAbi.encode_action("redeem", [collection, arguments.token_id]),
         resource: @resource,
         to: RedemptionAbi.redeemer_address(),
         contract_name: "AnimataRedeemer",
         risk_copy: @risk["redeem"],
         arguments: %{collection: collection, token_id: arguments.token_id}
       )}
    else
      step when is_atom(step) -> refusal(step)
      error -> error
    end
  end

  defp prepare_action("claim", _arguments, signer) do
    with {:ok, facts} <- ChainClient.module().overview(signer, nil, nil),
         :ok <- positive_claimable(facts) do
      {:ok,
       Envelope.new("claim", signer, RedemptionAbi.encode_action("claim", []),
         resource: @resource,
         to: RedemptionAbi.redeemer_address(),
         contract_name: "AnimataRedeemer",
         risk_copy: @risk["claim"],
         arguments: %{}
       )}
    end
  end

  defp prepare_action(_, _, _), do: {:error, :unknown_action}

  def next_step(%{token_id: nil}, _), do: :token_selection_required
  def next_step(%{nft_owner_unavailable: true}, _), do: :nft_owner_unavailable

  def next_step(facts, signer) do
    price = String.to_integer(RedemptionAbi.price_atomic())

    with {:ok, allowance} <- atomic(facts.usdc_allowance_raw),
         {:ok, balance} <- atomic(facts.usdc_balance_raw) do
      cond do
        not Address.equal?(facts.nft_owner, signer) -> :nft_not_owned
        facts.nft_approved != true -> :nft_approval_required
        allowance != price -> :exact_usdc_approval_required
        balance < price -> :insufficient_usdc
        true -> :ready
      end
    else
      :error -> :chain_unavailable
    end
  end

  defp current_wallet(address, context) do
    with {:ok, signer} <- normalize_address(address),
         {:ok, lease} <- lease(context),
         account when not is_nil(account) <-
           SessionAuthority.leased_account(lease.lineage, lease.account_id),
         :ok <- wallet_member(account, signer),
         do: {:ok, signer, lease}
  end

  defp return_current(lease, signer, envelope) do
    callback = fn account -> current_envelope(account, signer, envelope) end

    case SessionAuthority.transact_lease(lease.lineage, lease.account_id, callback) do
      {:error, :stale_authority} -> refusal(:session_unavailable)
      false -> refusal(:stale_or_invalid_action)
      result -> result
    end
  end

  defp current_envelope(account, signer, envelope) do
    with :ok <- wallet_member(account, signer),
         {:ok, target, contract} <- RedemptionAbi.action_identity(envelope),
         true <-
           Envelope.valid_for_confirmation?(envelope,
             resource: @resource,
             to: target,
             signer: signer,
             contract_name: contract,
             actions: @actions
           ),
         do: {:ok, envelope}
  end

  defp positive_claimable(facts) do
    case atomic(facts.claimable_raw) do
      {:ok, value} when value > 0 -> :ok
      {:ok, _} -> refusal(:nothing_claimable)
      :error -> refusal(:chain_unavailable)
    end
  end

  defp valid_token_id(id) when is_integer(id) and id in 1..999, do: :ok
  defp valid_token_id(_), do: {:error, :invalid_token_id}
  defp optional_collection(nil, nil), do: {:ok, nil}

  defp optional_collection(collection, nil) when is_binary(collection),
    do: RedemptionAbi.collection(collection)

  defp optional_collection(collection, token_id) when is_integer(token_id),
    do: RedemptionAbi.collection(collection)

  defp optional_collection(_, _), do: {:error, :invalid_token_selection}

  defp atomic(value) do
    case Integer.parse(value || "") do
      {amount, ""} -> {:ok, amount}
      _ -> :error
    end
  end

  defp lease(%{source_context: %{session_lease: %{lineage: lineage, account_id: account_id}}})
       when is_binary(lineage) and is_integer(account_id),
       do: {:ok, %{lineage: lineage, account_id: account_id}}

  defp lease(_), do: {:error, :session_lease_required}

  defp wallet_member(%{wallet_addresses: wallets}, signer),
    do:
      if(Enum.any?(wallets || [], &Address.equal?(&1, signer)),
        do: :ok,
        else: refusal(:wrong_signer)
      )

  defp normalize_address(value) do
    case Address.normalize(value) do
      {:ok, address} -> {:ok, address}
      :error -> {:error, :invalid_wallet}
    end
  end

  defp refusal(reason),
    do:
      {:error,
       Ash.Error.Invalid.Unavailable.exception(
         resource: AshPlatform.Redemption.Snapshot,
         reason: reason
       )}
end
