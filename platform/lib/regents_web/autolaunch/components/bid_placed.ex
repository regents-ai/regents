defmodule RegentsWeb.Autolaunch.Components.BidPlaced do
  @moduledoc """
  Where a chain's explorer shows a transaction or an address, for a token's
  revenue and the creator's wallet beside a launch. The note shown once a bid
  is placed comes with the bid window.
  """

  @doc "The chain's explorer page for a transaction."
  def transaction_url(:base, hash), do: "https://basescan.org/tx/#{hash}"

  @doc "The chain's explorer page for an address."
  def address_url(:base, address), do: "https://basescan.org/address/#{address}"

  def address_url(:robinhood, address),
    do: "https://robinhoodchain.blockscout.com/address/#{address}"
end
