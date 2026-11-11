defmodule Regents.BrowserStakingReading do
  @moduledoc """
  The staking reading the browser test server starts with. playwright.config.ts
  runs `warm!/0` before the server serves pages: the server's jobs only queue
  (Oban's manual testing mode), and the Stake pages need one reading from the
  test chain client. One wallet, the one the `valid-staking-usdc-short` bearer
  signs in with, reads a treasury that cannot pay its USDC yet.
  """

  alias Regents.Staking.SnapshotRefresh

  @usdc_short_wallet "0x4444444444444444444444444444444444444444"

  # A snooze means the browser database already holds a fresh reading.
  def warm! do
    Application.put_env(:regents, :test_staking_balances, %{
      @usdc_short_wallet => %{
        usdc_credited: "100000000",
        usdc_claimed: "100000000",
        usdc_residual: "0"
      }
    })

    case SnapshotRefresh.perform(%Oban.Job{}) do
      :ok -> :ok
      {:snooze, _seconds} -> :ok
    end
  end
end
