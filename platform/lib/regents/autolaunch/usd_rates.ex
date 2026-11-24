defmodule Regents.Autolaunch.UsdRates do
  @moduledoc """
  The dollar prices Autolaunch's figures are shown in, read together: REGENT's
  and each Base stock's.

  REGENT's is the staking side's stored reading (`Regents.Stake.SnapshotCache`,
  the `regent_price_usd` and `regent_price_read_at` of `Regents.Stake.Facts`),
  a price only while it was read within the last fifteen minutes; an older
  one is no price. A stock's is its Chainlink feed's
  (`Regents.Autolaunch.Stocks.MarketData`). A test network's coins carry no
  dollar value, so on one nothing is read and every price stays unknown.
  Robinhood's stock prices are not here yet, so a Robinhood auction has none.
  """

  alias Regents.Autolaunch.Lab
  alias Regents.Autolaunch.Robinhood.Lab, as: RobinhoodLab
  alias Regents.Autolaunch.Stocks.{Assets, MarketData}
  alias Regents.Stake.SnapshotCache

  @fresh_seconds 15 * 60

  @type t :: %{
          regent: Decimal.t() | nil,
          base: %{String.t() => Decimal.t()},
          robinhood: %{String.t() => Decimal.t()}
        }

  @doc "REGENT's price and each chain's stock prices, each unknown on a test network."
  @spec rates() :: t()
  def rates do
    %{
      regent: if(!Lab.test_chain?(), do: regent(DateTime.utc_now())),
      base: if(Lab.test_chain?(), do: %{}, else: MarketData.prices(:base)),
      robinhood: if(RobinhoodLab.test_chain?(), do: %{}, else: MarketData.prices(:robinhood))
    }
  end

  @doc "The USD price of one unit of an auction's currency from `rates/0`; nil while none is known."
  @spec auction_rate(t(), map()) :: Decimal.t() | nil
  def auction_rate(rates, auction) do
    cond do
      RobinhoodLab.chain?(auction.chain_id) ->
        stock_rate(Map.get(rates, :robinhood), auction.quote_token_symbol)

      auction.kind == :agent ->
        Map.get(rates, :regent)

      true ->
        stock_rate(Map.get(rates, :base), auction.quote_token_symbol)
    end
  end

  defp stock_rate(prices, symbol) when is_map(prices) and is_binary(symbol),
    do: prices[Assets.ticker(symbol)]

  defp stock_rate(_prices, _symbol), do: nil

  defp regent(now) do
    case SnapshotCache.snapshot() do
      %{regent_price_usd: price, regent_price_read_at: %DateTime{} = read_at}
      when is_binary(price) ->
        if DateTime.diff(now, read_at) <= @fresh_seconds, do: positive(price)

      _none ->
        nil
    end
  end

  defp positive(price) do
    case Decimal.parse(price) do
      {decimal, ""} -> if Decimal.gt?(decimal, 0), do: decimal
      _unparsed -> nil
    end
  end
end
