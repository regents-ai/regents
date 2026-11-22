defmodule Regents.Autolaunch.Stocks.PriceCache do
  @moduledoc """
  Each stock's dollar price as its Chainlink feed last answered, by feed
  address, kept on this machine for ten minutes and shared by every page that
  asks (`Regents.Autolaunch.Stocks.MarketData`). A feed that did not answer is
  not kept: the next reader asks it again.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  @kept :timer.minutes(10)

  @doc "The price kept under `feed`, or `read`'s answer, kept ten minutes when it is `{:ok, price}`."
  @spec price(String.t(), (-> {:ok, Decimal.t()} | {:error, term()})) ::
          {:ok, Decimal.t()} | {:error, term()}
  def price(feed, read), do: fetch_or_store(feed, read, ttl: @kept)
end
