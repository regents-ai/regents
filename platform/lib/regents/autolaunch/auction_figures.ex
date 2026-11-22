defmodule Regents.Autolaunch.AuctionFigures do
  @moduledoc """
  The launch figures an auction's stored record gives, worked out once for the
  market cards: so far, when to say it is short of its minimum.
  """

  @closing_seconds 30 * 60

  @doc """
  The moment from which to tell bidders the auction is short of its minimum:
  30 minutes before bidding is due to end, and only while everything bid so far
  adds up to less than the minimum. Nil when the auction is not live, its bids
  cover the minimum, or either figure is not recorded yet. Every minimum is
  tiny beside a real auction's bids, so at any other time it is not shown.
  """
  @spec minimum_warning_from(map()) :: DateTime.t() | nil
  def minimum_warning_from(
        %{state: :active, estimated_end_at: %DateTime{} = end_at, bid_volume: %Decimal{} = bids} =
          auction
      ) do
    if Decimal.lt?(bids, minimum(auction)), do: DateTime.add(end_at, -@closing_seconds)
  end

  def minimum_warning_from(_auction), do: nil

  # What the auction must raise to launch, in whole quote-token units: the
  # required raise plus one base unit, because the auction may count a bid
  # placed after its first block one base unit short.
  defp minimum(%{required_currency_raised: required, quote_token_decimals: decimals}),
    do: Decimal.new(1, String.to_integer(required) + 1, -decimals)
end
