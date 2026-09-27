defmodule AshPlatform.Redemption.Actions do
  @moduledoc false
  alias AshPlatform.Redemption.ChainClient
  alias AshPlatform.WalletActions.{Address, RedemptionAbi}

  def overview(_input, _context), do: ChainClient.module().overview(nil, nil, nil)

  def account_for_wallet(input, _context) do
    with {:ok, signer} <- Address.normalize_wallet(input.arguments.expected_signer),
         {:ok, collection} <-
           optional_collection(input.arguments.collection, input.arguments.token_id),
         do: ChainClient.module().overview(signer, collection, input.arguments.token_id)
  end

  @doc """
  The step the last Base reading says a selection needs, for the page's stepper
  and its hint copy. It never decides which wallet steps the page offers.
  """
  def next_step(%{token_id: nil}, _), do: :token_selection_required
  def next_step(%{nft_redeemed: true}, _), do: :nft_redeemed
  def next_step(%{nft_owner_unavailable: true}, _), do: :nft_owner_unavailable

  def next_step(facts, signer) do
    price = String.to_integer(RedemptionAbi.price_atomic())

    with {:ok, allowance} <- atomic(facts.usdc_allowance_raw),
         {:ok, balance} <- atomic(facts.usdc_balance_raw) do
      cond do
        not Address.equal?(facts.nft_owner, signer) -> :nft_not_owned
        facts.nft_approved != true -> :nft_approval_required
        allowance < price -> :exact_usdc_approval_required
        balance < price -> :insufficient_usdc
        true -> :ready
      end
    else
      :error -> :chain_unavailable
    end
  end

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
end
