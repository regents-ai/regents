defmodule Regents.Autolaunch.LaunchActions do
  @moduledoc """
  A Revstake launch's fixed schedule, which the pages state in words. Only the
  schedule is here: preparing a founder's launch for their wallet comes with
  the page that launches.
  """

  alias Regents.Autolaunch.Lab

  @doc """
  A Revstake launch's fixed schedule in Base blocks on strategy `version`,
  its START_DELAY_BLOCKS, AUCTION_DURATION_BLOCKS, CLAIM_DELAY_BLOCKS and
  MIGRATION_DELAY_BLOCKS: bidding opens `opens` after the launch, runs for
  `length`, and claims and the trading pool open `claim` and `pool` after
  bidding ends. Version 3 restates version 2's for five blocks a second. The
  treasury's release is counted in time (365 days), not here.
  """
  def schedule(:v2), do: %{opens: 300, length: 86_401, claim: 64, pool: 128}
  def schedule(:v3), do: %{opens: 3_000, length: 864_001, claim: 640, pool: 1_280}

  @doc "The schedule of a new launch: on the strategy the Base description names for new launches."
  def schedule, do: schedule(Lab.current!().version)
end
