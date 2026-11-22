defmodule Regents.Autolaunch.Stocks.PriceCache do
  @moduledoc """
  Each stock's dollar price as its Chainlink feed last answered, by feed
  address, kept on this machine and shared by every page that asks
  (`Regents.Autolaunch.Stocks.MarketData`). A price is kept ten minutes. A
  feed that gave none is kept a minute as having none, so whoever opens the
  page, an unanswering feed is asked at most once a minute.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  @kept :timer.minutes(10)
  @unanswered_kept :timer.minutes(1)

  @doc "The answer kept under `feed`, or `read`'s, kept ten minutes for a price and one for none."
  @spec price(String.t(), (-> {:ok, Decimal.t()} | {:error, term()})) ::
          {:ok, Decimal.t()} | {:error, term()}
  def price(feed, read) do
    case get!(feed) do
      nil -> read_and_keep(feed, read)
      answer -> answer
    end
  end

  defp read_and_keep(feed, read) do
    answer = read.()
    put!(feed, answer, ttl: kept(answer))
    answer
  end

  defp kept({:ok, _price}), do: @kept
  defp kept({:error, _reason}), do: @unanswered_kept
end
