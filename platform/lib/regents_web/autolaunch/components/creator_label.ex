defmodule RegentsWeb.Autolaunch.Components.CreatorLabel do
  @moduledoc """
  Who launched an auction or token, in a word or two, the same on every list
  row: the creator's first account shown as ownership checked (X, Company X,
  ENS, then GitHub), else the launching wallet, shortened.
  """

  alias Regents.Autolaunch.Robinhood.Lab, as: RobinhoodLab
  alias RegentsWeb.Autolaunch.Components.{BidPlaced, MarketCard}

  @doc """
  The creator's name for `auction`, given its creator's connected accounts:
  its words, where it leads and what it says on hover. Nil when the auction
  names neither an account nor a wallet.
  """
  @spec name(map(), map() | nil) :: %{text: String.t(), url: String.t(), title: String.t()} | nil
  def name(auction, connections) do
    case MarketCard.connection_list(connections) do
      [account | _rest] ->
        %{
          text: account.handle,
          url: account.url,
          title: "#{account.label} #{account.handle}, ownership checked"
        }

      [] ->
        wallet(auction)
    end
  end

  defp wallet(%{creator_address: address, chain_id: chain_id}) when is_binary(address) do
    chain = if RobinhoodLab.chain?(chain_id), do: :robinhood, else: :base

    %{
      text: RegentFormat.short_address(address),
      url: BidPlaced.address_url(chain, address),
      title: address
    }
  end

  defp wallet(_auction), do: nil
end
