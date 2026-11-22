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
  built from the page's own reading (`Regents.Techtree.WalletBench.Reading`),
  so the feed and the page always agree; `read_at` is when that reading was
  taken. It names every field it carries.
  """
  use RegentsWeb, :verified_routes

  alias Regents.Techtree.WalletBench.Reading
  alias RegentsWeb.Techtree.WalletBenchCopy, as: Copy

  @doc "The feed built from one reading of the bench."
  @spec feed(Reading.t()) :: map()
  def feed(%{attempts: attempts, read_at: read_at}) do
    %{
      page: url(~p"/techtree/wallet-bench"),
      read_at: read_at,
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
