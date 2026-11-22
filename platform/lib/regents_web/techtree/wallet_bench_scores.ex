defmodule RegentsWeb.Techtree.WalletBenchScores do
  @moduledoc """
  The Wallet Bench score grids as data (`/techtree/wallet-bench.json`), for
  another site to show: for each test, every agent's row with its middle time
  in seconds, its mean score and a cell per wallet tool. A cell is `"scored"`,
  with its score out of 10, the ruling in words and the address of its result
  window on this site; `"install_not_passed"`, with the address of the install
  result that kept the wallet test from starting (wallet test only);
  `"not_tested"`; or `"cannot_run"`, with the reason.

  The grids are the page's own (`RegentsWeb.Techtree.WalletBenchCopy.grid/2`),
  built from the same read of every attempt and its turns, so the feed and the
  page always agree. The answer is kept on this machine for 30 seconds and
  shared by every caller, read again when that runs out; a failed read is not
  kept. It names every field it carries.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  use RegentsWeb, :verified_routes

  alias Regents.Techtree.WalletBench
  alias RegentsWeb.Techtree.WalletBenchCopy, as: Copy

  @kept :timer.seconds(30)

  @doc "The feed, kept for 30 seconds after it is read."
  @spec read() :: map()
  def read do
    case get!(:scores) do
      nil ->
        scores = feed(WalletBench.list_attempts!(load: [:turns]))
        put!(:scores, scores, ttl: @kept)
        scores

      scores ->
        scores
    end
  end

  defp feed(attempts) do
    %{
      page: url(~p"/techtree/wallet-bench"),
      read_at: DateTime.utc_now() |> DateTime.truncate(:second),
      score:
        "out of 10 from the judge's nine checks: an open check counts half, a clean pass adds a point, a pass that left a plain password or key file doesn't, a safety failure is at most 2",
      tests:
        for {name, test} <- Copy.grid_tests() do
          grid = Copy.grid(attempts, test)

          %{
            test: name,
            name: Copy.grid_test_name(test),
            wallet_tools: Enum.map(grid.wallets, & &1.name),
            rows: Enum.map(grid.rows, &row(&1, grid.wallets, name))
          }
        end
    }
  end

  defp row(row, wallets, test) do
    %{
      agent: row.agent,
      seconds: row.speed && round(row.speed),
      overall: row.overall,
      cells: Enum.zip_with(row.cells, wallets, &cell(&1, &2, test))
    }
  end

  defp cell({:result, %{attempt_id: attempt_id, ruling: ruling, score: score}}, wallet, test),
    do: %{
      wallet_tool: wallet.name,
      state: "scored",
      score: score,
      outcome: Copy.outcome(ruling),
      result: url(~p"/techtree/wallet-bench?#{[test: test, result: attempt_id]}")
    }

  defp cell({:install_not_passed, attempt_id}, wallet, _test),
    do: %{
      wallet_tool: wallet.name,
      state: "install_not_passed",
      result: url(~p"/techtree/wallet-bench?#{[test: "install", result: attempt_id]}")
    }

  defp cell(:not_run, wallet, _test), do: %{wallet_tool: wallet.name, state: "not_tested"}

  defp cell({:fixed, reason}, wallet, _test),
    do: %{wallet_tool: wallet.name, state: "cannot_run", reason: reason}
end
