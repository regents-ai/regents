defmodule Regents.Autolaunch.Stocks.LaunchActions do
  @moduledoc """
  A Memestock launch's fixed schedule and how its creator's tokens are
  released, which the pages state in words. Only these are here: preparing a
  creator's launch for their wallet comes with the page that launches.
  """

  alias Regents.Autolaunch.LaunchChain
  alias Regents.Autolaunch.Stocks.Lab

  # The presets' schedules, from StocksPreset.sol in contracts/stocks-v2
  # and contracts/stocks-v3 on Base and contracts/robinhood-v2/src/RobinhoodPreset.sol
  # on Robinhood Chain, where blocks are the rollup clock's. Only the schedule
  # differs: Base's third launchpad restates the second's for five blocks a
  # second and vests the creator by the clock.
  @schedules %{
    {:base, :v2} => %{
      opens: 300,
      length: 43_200,
      claim: 64,
      pool: 128,
      vesting: {:blocks, 1_296_000}
    },
    {:base, :v3} => %{
      opens: 3_000,
      length: 431_991,
      claim: 640,
      pool: 1_280,
      vesting: {:seconds, 2_592_000}
    },
    {:robinhood, :v2} => %{
      opens: 6_000,
      length: 864_000,
      claim: 1_280,
      pool: 2_560,
      vesting: {:blocks, 25_920_000}
    }
  }

  @doc """
  A Memestock launch's fixed schedule on `chain` for launchpad `version`, in
  blocks: bidding opens `opens` after the launch, runs for `length`, claims
  and the trading pool open `claim` and `pool` after bidding ends, and the
  creator's tokens are released over `vesting` from the pool opening, counted
  in `{:blocks, count}` or, on Base's third launchpad, `{:seconds, count}`.
  Every duration the site states for a Memestock launch is worked out from
  these with `LaunchChain.time_estimate/2`.
  """
  def schedule(chain, version), do: Map.fetch!(@schedules, {chain, version})

  @doc """
  The schedule of a new launch on `chain`: on Base, the launchpad the Base
  Stocks description names for new launches (`Regents.Autolaunch.Stocks.Lab`).
  """
  def schedule(:base), do: schedule(:base, Lab.current!().version)
  def schedule(:robinhood), do: schedule(:robinhood, :v2)

  @doc """
  How the creator's tokens of a new launch on `chain` are released, in words:
  "block by block over about 3 days", or "steadily over 30 days" where the
  launchpad vests by the clock. Pages say it from graduation.
  """
  def release(chain), do: release_words(chain, schedule(chain).vesting)

  defp release_words(chain, {:blocks, blocks}),
    do: "block by block over #{LaunchChain.time_estimate(chain, blocks)}"

  defp release_words(_chain, {:seconds, seconds}),
    do: "steadily over #{div(seconds, 86_400)} days"
end
