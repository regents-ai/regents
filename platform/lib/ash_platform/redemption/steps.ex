defmodule AshPlatform.Redemption.Steps do
  @moduledoc """
  The wallet steps behind the Redeem page's buttons, built on the server with
  `regent_chain` and pushed to the page before anyone presses.

  Approving exactly 80 USDC and claiming unlocked REGENT are always steps.
  Approving the NFT collection is a step once an Animata collection is chosen,
  and redeeming once a token ID from 1 to 999 is chosen too. The last reading
  from Base never takes a step away: Base decides whether each one goes through.
  """

  alias AshPlatform.WalletActions.RedemptionAbi
  alias RegentChain.Review

  @doc """
  The steps from the selection on screen: the collection id and the token ID as
  typed. None of them names its sender, so any signer sends the same steps.
  """
  def steps(%{collection: collection, token_id: token_id}) do
    case RedemptionAbi.collection(collection) do
      {:ok, address} ->
        [approve_collection(address), approve_usdc()] ++
          redeem(address, token_id(token_id)) ++ [claim()]

      {:error, :invalid_collection} ->
        [approve_usdc(), claim()]
    end
  end

  @doc "The token ID typed in, when it is one the redeemer takes."
  def token_id(input) when is_binary(input) do
    case Integer.parse(input) do
      {id, ""} when id in 1..999//1 -> {:ok, id}
      _other -> :error
    end
  end

  def token_id(_input), do: :error

  defp approve_collection(address),
    do:
      Review.step(
        "approve_nft_collection",
        address,
        RedemptionAbi.encode_erc721("set_approval_for_all", [redeemer(), true])
      )

  defp approve_usdc,
    do:
      Review.step(
        "approve_exact_usdc",
        RedemptionAbi.usdc_address(),
        RedemptionAbi.encode_erc20("approve", [
          redeemer(),
          String.to_integer(RedemptionAbi.price_atomic())
        ])
      )

  defp redeem(address, {:ok, id}),
    do: [Review.step("redeem", redeemer(), RedemptionAbi.encode_action("redeem", [address, id]))]

  defp redeem(_address, :error), do: []

  defp claim,
    do: Review.step("claim", redeemer(), RedemptionAbi.encode_action("claim", []))

  defp redeemer, do: RedemptionAbi.redeemer_address()
end
