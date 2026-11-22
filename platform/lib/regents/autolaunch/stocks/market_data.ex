defmodule Regents.Autolaunch.Stocks.MarketData do
  @moduledoc """
  The dollar price of each Base stock, for the figures of the auctions bid in
  it. Stock prices come from the Chainlink feed each stock's route names, read
  through the site's own Base address (`Regents.Chain.Rpc`, failures counted
  under the scope "autolaunch stock prices").

  Each feed's answer is kept for ten minutes (`Regents.Autolaunch.Stocks.PriceCache`).
  A feed that did not answer is not kept: the next page to open asks it again.
  The answers are read straight from their cache, never through one process.

  Robinhood's stock prices come with Robinhood's part.
  """

  alias Regents.Autolaunch.Stocks.{Assets, PriceCache}
  alias Regents.Chain.Rpc

  @latest_round_data "0xfeaf968c"
  # Every stock's Chainlink feed, which its route names, answers in USD with
  # eight decimals.
  @feed_decimals 8
  @feed_max_age_seconds 7 * 24 * 60 * 60
  @rpc_opts [scope: "autolaunch stock prices"]

  @doc """
  USD prices by ticker for every saved Base stock whose feed answered; none
  while the saved stocks cannot be read.
  """
  @spec prices(:base) :: %{String.t() => Decimal.t()}
  def prices(:base) do
    case Assets.known(:base) do
      {:ok, stocks} -> stocks |> feeds() |> read_prices()
      {:error, _reason} -> %{}
    end
  end

  # The feed of each saved stock whose route names one, by ticker, so an
  # auction in a revoked stock keeps its dollar figures. Where a chain has two
  # stocks under one ticker, the admitted one's feed.
  defp feeds(stocks) do
    for %{symbol: symbol, feed: feed} <- Enum.sort_by(stocks, & &1.admitted),
        feed,
        into: %{},
        do: {Assets.ticker(symbol), feed}
  end

  # One `latestRoundData()` per feed not kept, read concurrently; a feed that
  # does not answer leaves its ticker out.
  defp read_prices(feeds) do
    feeds
    |> Task.async_stream(
      fn {ticker, feed} -> {ticker, PriceCache.price(feed, fn -> read_price(feed) end)} end,
      max_concurrency: 4,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {ticker, {:ok, price}}} -> [{ticker, price}]
      _unanswered -> []
    end)
    |> Map.new()
  end

  defp read_price(feed) do
    now = System.os_time(:second)

    # roundId, signed answer, startedAt, updatedAt, answeredInRound
    with {:ok, "0x" <> hex} when byte_size(hex) == 320 <-
           Rpc.request("eth_call", [%{to: feed, data: @latest_round_data}, "latest"], @rpc_opts),
         {:ok, <<_round::256, answer::signed-256, _started::256, updated::256, _answered::256>>} <-
           Base.decode16(hex, case: :mixed),
         true <-
           answer > 0 and updated > 0 and updated <= now and
             now - updated <= @feed_max_age_seconds do
      {:ok, Decimal.div(Decimal.new(answer), Integer.pow(10, @feed_decimals))}
    else
      _unavailable -> {:error, :unavailable}
    end
  end
end
