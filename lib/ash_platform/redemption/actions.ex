defmodule AshPlatform.Redemption.Actions do
  @moduledoc false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.Human
  alias AshPlatform.Redemption.ChainClient
  alias AshPlatform.WalletActions.{Abi, Envelope, RedemptionAbi, StakeRedeemOperations}

  @capability :redeem
  @resource "animata_redemption"
  @actions ~w(approve_nft_collection approve_exact_usdc redeem claim)
  @risk %{
    "approve_nft_collection" =>
      "Allow the verified Animata redeemer to transfer NFTs from this collection. This approval applies to the whole selected collection until you revoke it.",
    "approve_exact_usdc" =>
      "Approve exactly 80 USDC for the verified Animata redeemer. This replaces the current allowance with 80 USDC.",
    "redeem" =>
      "Transfer the selected Animata NFT and exactly 80 USDC to start a seven-day stream of 5 million REGENT and receive the mapped Regents Club token.",
    "claim" => "Claim all REGENT currently unlocked from your redemption vest."
  }

  def overview(_input, _context), do: ChainClient.module().overview(nil, nil, nil)

  def account(input, %{actor: %Human{} = actor}) do
    with {:ok, wallet} <- verified_primary_wallet(actor),
         {:ok, collection} <-
           optional_collection(input.arguments.collection, input.arguments.token_id) do
      ChainClient.module().overview(wallet, collection, input.arguments.token_id)
    end
  end

  def account(_input, _context), do: {:error, :authentication_required}

  # The provider reads happen here, before the lease transaction; only the
  # resulting operation row is written inside it.
  def prepare(action, input, %{actor: %Human{} = actor} = context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         :ok <- verified_wallet(actor, signer),
         {:ok, envelope} <- prepare_action(action, input.arguments, signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         {:ok, _operation} <- StakeRedeemOperations.prepare(lease, @capability, envelope) do
      {:ok, envelope}
    end
  end

  def prepare(_action, _input, _context), do: {:error, :authentication_required}

  def confirm(input, %{actor: %Human{} = actor} = context) do
    envelope = atomize_envelope(input.arguments.envelope)

    with {:ok, target, contract_name} <- identity_for(envelope),
         true <- valid_for_confirmation?(envelope, target, contract_name),
         :ok <- verified_wallet(actor, envelope.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         # Confirmation and every retry run against the stored submitted
         # identity: an exact replay passes, a different hash is refused.
         {:ok, _identity} <-
           StakeRedeemOperations.bind_hash(
             lease,
             @capability,
             envelope.action_id,
             :action,
             input.arguments.transaction_hash
           ) do
      envelope
      |> ChainClient.module().confirm(input.arguments.transaction_hash)
      |> record_action_outcome(lease, envelope, input.arguments.transaction_hash)
    else
      false -> {:error, :stale_or_invalid_action}
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm(_input, _context), do: {:error, :authentication_required}

  # Receipt and reread are recorded as they become known. Only their agreement
  # reaches the terminal `:confirmed` state.
  defp record_action_outcome({:ok, %{reread_verified: true} = result}, lease, envelope, _hash) do
    with {:ok, _receipt} <- record_receipt(lease, envelope),
         {:ok, _confirmed} <-
           StakeRedeemOperations.confirm(lease, @capability, envelope.action_id) do
      {:ok, result}
    end
  end

  defp record_action_outcome({:ok, result}, lease, envelope, _hash) do
    with {:ok, _receipt} <- record_receipt(lease, envelope), do: {:ok, result}
  end

  defp record_action_outcome({:error, :transaction_reverted}, lease, envelope, hash) do
    with {:ok, _reverted} <-
           StakeRedeemOperations.record_revert(
             lease,
             @capability,
             envelope.action_id,
             :action,
             "verified revert on Base"
           ) do
      {:ok,
       %{
         transaction_hash: hash,
         receipt_verified: true,
         transaction_reverted: true,
         reread_verified: false,
         redemption: nil
       }}
    end
  end

  defp record_action_outcome({:error, reason}, _lease, _envelope, _hash), do: {:error, reason}

  defp record_receipt(lease, envelope),
    do: StakeRedeemOperations.record_receipt(lease, @capability, envelope.action_id, :action)

  @doc false
  def claim_dispatch(input, context) do
    operate(
      context,
      &StakeRedeemOperations.claim_dispatch(&1, @capability, input.arguments.action_id, :action)
    )
  end

  @doc false
  def bind_hash(input, context) do
    operate(
      context,
      &StakeRedeemOperations.bind_hash(
        &1,
        @capability,
        input.arguments.action_id,
        :action,
        input.arguments.transaction_hash
      )
    )
  end

  @doc false
  def close_not_sent(input, context) do
    operate(
      context,
      &StakeRedeemOperations.close_not_sent(
        &1,
        @capability,
        input.arguments.action_id,
        :action,
        "wallet reported an explicit user rejection"
      )
    )
  end

  @doc false
  def cancel_operation(input, context) do
    operate(
      context,
      &StakeRedeemOperations.cancel(
        &1,
        @capability,
        input.arguments.action_id,
        "review withdrawn before dispatch"
      )
    )
  end

  @doc false
  def active_operation(_input, %{actor: %Human{} = actor}) do
    with {:ok, operation} <- StakeRedeemOperations.active(actor.human_account_id, @capability),
         do: {:ok, %{operation: StakeRedeemOperations.view(operation)}}
  end

  def active_operation(_input, _context), do: {:error, :authentication_required}

  defp operate(%{actor: %Human{}} = context, transition) do
    with {:ok, lease} <- StakeRedeemOperations.lease(context),
         {:ok, operation} <- transition.(lease) do
      {:ok, %{operation: StakeRedeemOperations.view(operation)}}
    end
  end

  defp operate(_context, _transition), do: {:error, :authentication_required}

  def restore(input, %{actor: %Human{} = actor}) do
    envelope = atomize_envelope(input.arguments.envelope)

    with {:ok, target, contract_name} <- identity_for(envelope),
         true <- valid_for_confirmation?(envelope, target, contract_name),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      {:ok, envelope}
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  def restore(_input, _context), do: {:error, :authentication_required}

  defp prepare_action("approve_nft_collection", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection) do
      redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())
      data = RedemptionAbi.encode_erc721("set_approval_for_all", [redeemer, true])

      {:ok,
       Envelope.new("approve_nft_collection", signer, data,
         resource: @resource,
         to: collection,
         contract_name: collection_name(collection),
         risk_copy: @risk["approve_nft_collection"],
         arguments: %{collection: collection, operator: redeemer, approved: true}
       )}
    end
  end

  defp prepare_action("approve_exact_usdc", _arguments, signer) do
    redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())
    usdc = Abi.normalize_address!(RedemptionAbi.usdc_address())
    amount = String.to_integer(RedemptionAbi.price_atomic())
    data = RedemptionAbi.encode_erc20("approve", [redeemer, amount])

    {:ok,
     Envelope.new("approve_exact_usdc", signer, data,
       resource: @resource,
       to: usdc,
       contract_name: "USDC",
       risk_copy: @risk["approve_exact_usdc"],
       arguments: %{
         spender: redeemer,
         amount_atomic: Integer.to_string(amount),
         mode: "exact"
       }
     )}
  end

  defp prepare_action("redeem", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection),
         :ok <- valid_token_id(arguments.token_id),
         {:ok, facts} <- ChainClient.module().overview(signer, collection, arguments.token_id),
         :ok <- eligible_to_redeem(facts, signer) do
      data = RedemptionAbi.encode_action("redeem", [collection, arguments.token_id])

      {:ok,
       Envelope.new("redeem", signer, data,
         resource: @resource,
         to: RedemptionAbi.redeemer_address(),
         contract_name: "AnimataRedeemer",
         risk_copy: @risk["redeem"],
         arguments: %{collection: collection, token_id: arguments.token_id}
       )}
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

  defp prepare_action(_action, _arguments, _signer), do: {:error, :unknown_action}

  defp eligible_to_redeem(facts, signer) do
    cond do
      normalize_or_nil(facts.nft_owner) != signer ->
        {:error, :nft_not_owned}

      facts.nft_approved != true ->
        {:error, :nft_approval_required}

      parse_integer(facts.usdc_balance_raw) < String.to_integer(RedemptionAbi.price_atomic()) ->
        {:error, :insufficient_usdc}

      parse_integer(facts.usdc_allowance_raw) != String.to_integer(RedemptionAbi.price_atomic()) ->
        {:error, :exact_usdc_approval_required}

      true ->
        :ok
    end
  end

  defp positive_claimable(facts) do
    if parse_integer(facts.claimable_raw) > 0,
      do: :ok,
      else: {:error, :nothing_claimable}
  end

  defp valid_token_id(token_id)
       when is_integer(token_id) and token_id >= 1 and token_id <= 999,
       do: :ok

  defp valid_token_id(_token_id), do: {:error, :invalid_token_id}

  defp optional_collection(nil, nil), do: {:ok, nil}

  defp optional_collection(collection, nil) when is_binary(collection),
    do: RedemptionAbi.collection(collection)

  defp optional_collection(collection, token_id) when is_integer(token_id),
    do: RedemptionAbi.collection(collection)

  defp optional_collection(_collection, _token_id), do: {:error, :invalid_token_selection}

  defp identity_for(%{action: "approve_nft_collection", arguments: arguments}) do
    collection = field(arguments, :collection)

    case RedemptionAbi.collection_id(collection) do
      nil -> {:error, :invalid_collection}
      _id -> {:ok, Abi.normalize_address!(collection), collection_name(collection)}
    end
  end

  defp identity_for(%{action: "approve_exact_usdc"}),
    do: {:ok, Abi.normalize_address!(RedemptionAbi.usdc_address()), "USDC"}

  defp identity_for(%{action: action}) when action in ["redeem", "claim"],
    do: {:ok, Abi.normalize_address!(RedemptionAbi.redeemer_address()), "AnimataRedeemer"}

  defp identity_for(_envelope), do: {:error, :invalid_action}

  defp valid_for_confirmation?(envelope, target, contract_name) do
    Envelope.valid_for_confirmation?(envelope,
      resource: @resource,
      to: target,
      signer: envelope.expected_signer,
      contract_name: contract_name,
      actions: @actions
    )
  end

  defp verified_primary_wallet(actor) do
    with {:ok, account} <- Accounts.get_human_account(actor.human_account_id, actor: actor),
         wallet when is_binary(wallet) <- normalize_or_nil(account.wallet_address) do
      {:ok, wallet}
    else
      _ -> {:error, :wallet_required}
    end
  end

  defp verified_wallet(%Human{} = actor, signer) do
    with {:ok, account} <- Accounts.get_human_account(actor.human_account_id, actor: actor),
         wallets when is_list(wallets) <- account.wallet_addresses,
         true <- Enum.any?(wallets, &(normalize_or_nil(&1) == signer)) do
      :ok
    else
      _ -> {:error, :wrong_signer}
    end
  end

  defp normalize_address(value) do
    {:ok, Abi.normalize_address!(value)}
  rescue
    _ -> {:error, :invalid_wallet}
  end

  defp normalize_or_nil(value) do
    Abi.normalize_address!(value)
  rescue
    _ -> nil
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> -1
    end
  end

  defp parse_integer(_value), do: -1

  defp collection_name(collection) do
    case RedemptionAbi.collection_id(collection) do
      "animata_i" -> "Animata I"
      "animata_ii" -> "Animata II"
    end
  end

  defp atomize_envelope(envelope) when is_map(envelope) do
    %{
      action_id: field(envelope, :action_id),
      idempotency_key: field(envelope, :idempotency_key),
      resource: field(envelope, :resource),
      action: field(envelope, :action),
      chain_id: field(envelope, :chain_id),
      to: field(envelope, :to),
      value: field(envelope, :value),
      data: field(envelope, :data),
      expected_signer: field(envelope, :expected_signer),
      prepared_at: field(envelope, :prepared_at),
      expires_at: field(envelope, :expires_at),
      risk_copy: field(envelope, :risk_copy),
      approval: field(envelope, :approval),
      arguments: atomize_arguments(field(envelope, :arguments) || %{}),
      metadata: field(envelope, :metadata),
      confirmation_token: field(envelope, :confirmation_token)
    }
  end

  defp atomize_arguments(arguments) when is_map(arguments) do
    Map.new(arguments, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
  rescue
    _ -> %{}
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
