defmodule Regents.BrowserStakingReading do
  @moduledoc """
  The staking reading the browser test server starts with. playwright.config.ts
  runs `warm!/0` before the server serves pages: the server's jobs only queue
  (Oban's manual testing mode), and the Stake pages need one reading from the
  test chain client.
  """

  alias Regents.Staking.SnapshotRefresh

  # A snooze means the browser database already holds a fresh reading.
  def warm! do
    case SnapshotRefresh.perform(%Oban.Job{}) do
      :ok -> :ok
      {:snooze, _seconds} -> :ok
    end
  end
end
