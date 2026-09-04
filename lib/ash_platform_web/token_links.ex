defmodule AshPlatformWeb.TokenLinks do
  @moduledoc """
  Where a visitor goes to buy REGENT or to look at its chart.

  The buy link names the same token address the staking page reads its figures
  from, so what a visitor is offered and what the page reports can never drift
  apart. The chart names the pool the token trades in, the same pool the market
  cap is priced from.
  """

  alias AshPlatform.Staking.PriceClient
  alias AshPlatform.WalletActions.Abi

  @doc "Where REGENT is bought."
  def buy, do: "https://app.uniswap.org/explore/tokens/base/#{Abi.stake_token_address()}"

  @doc "Where REGENT's chart is."
  def chart, do: "https://dexscreener.com/base/#{PriceClient.pool()}"
end
