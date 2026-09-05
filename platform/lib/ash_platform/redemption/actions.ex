defmodule AshPlatform.Redemption.Actions do
  @moduledoc false
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

  def account_for_wallet(input, _context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         {:ok, collection} <-
           optional_collection(input.arguments.collection, input.arguments.token_id),
         do: ChainClient.module().overview(signer, collection, input.arguments.token_id)
  end

  def prepare(action, input, _context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         {:ok, envelope} <- prepare_action(action, input.arguments, signer),
         {:ok, target, contract} <- RedemptionAbi.action_identity(envelope),
         true <-
           Envelope.valid_for_confirmation?(envelope,
             resource: @resource,
             to: target,
             signer: signer,
             contract_name: contract,
             actions: @actions
           ) do
      {:ok, envelope}
    else
      false -> refusal(:stale_or_invalid_action)
      error -> error
    end
  end

  # Each action's calldata is fixed by the action, the collection and the token
  # id the customer selected. Base decides whether the transaction succeeds.
  defp prepare_action("approve_nft_collection", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection) do
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
    end
  end

  defp prepare_action("approve_exact_usdc", arguments, signer) do
    with {:ok, _collection} <- RedemptionAbi.collection(arguments.collection) do
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
    end
  end

  defp prepare_action("redeem", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection),
         :ok <- valid_token_id(arguments.token_id) do
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
    end
  end

  defp prepare_action("claim", _arguments, signer),
    do:
      {:ok,
       Envelope.new("claim", signer, RedemptionAbi.encode_action("claim", []),
         resource: @resource,
         to: RedemptionAbi.redeemer_address(),
         contract_name: "AnimataRedeemer",
         risk_copy: @risk["claim"],
         arguments: %{}
       )}

  defp prepare_action(_, _, _), do: {:error, :unknown_action}

  @doc """
  The step the last Base reading says a selection needs, for the page's stepper
  and its hint copy. It never decides whether an action may be prepared.
  """
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
