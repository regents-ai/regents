defmodule RegentsWeb.Techtree.WalletBenchEvidenceController do
  @moduledoc """
  A wallet test's record on its own as JSON. One recorded file and the whole
  test as a zip are served by techtree.sh, which holds the stored files; the
  pages link there.

  When the database can't be read (`RegentsWeb.Techtree.Outage`) it answers 503
  asking to try again, never a 500 or a 404.
  """

  use RegentsWeb, :controller

  alias Regents.Techtree.WalletBench
  alias Regents.Techtree.WalletBench.Catalog
  alias RegentsWeb.Techtree.{ExactResponse, Outage}
  alias RegentsWeb.Techtree.WalletBenchCopy, as: Copy

  @load [:machine, :turns, :payments, :model_spend_usd, :judge_cost_usd]

  @doc """
  The test's `results.json` on its own, the same record techtree.sh's zip
  starts with, for an agent that reads the test without downloading its files.
  A test still running changes, so a caller may keep it for 30 seconds, as the
  scores.
  """
  def summary(conn, %{"id" => id}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, {attempt, events}} <- Outage.read(fn -> read(id) end) do
      conn
      |> put_resp_header("cache-control", "public, max-age=30")
      |> json(record(attempt, events))
    else
      :database_down ->
        conn
        |> put_resp_header("retry-after", "30")
        |> ExactResponse.send_error(
          503,
          :wallet_test_unavailable,
          "the wallet test can't be read right now; try again shortly",
          "Wait the seconds in the Retry-After header, then ask again."
        )

      _missing ->
        ExactResponse.send_error(
          conn,
          404,
          :wallet_test_not_found,
          "no wallet test has that id",
          "A test's id is the result in a score's address at #{url(~p"/techtree/wallet-bench.json")}."
        )
    end
  end

  # The test with its timeline, or nil when no test has that id.
  defp read(id) do
    case WalletBench.get_attempt!(id, load: @load, not_found_error?: false) do
      nil -> nil
      attempt -> {attempt, WalletBench.list_attempt_events!(attempt.id)}
    end
  end

  # What the test's page shows, field by field: every value is named here, so
  # nothing else the bench keeps on a test can reach the record. The ids are
  # the ones the scores at /techtree/wallet-bench.json name.
  defp record(attempt, events) do
    %{
      id: attempt.id,
      harness_id: attempt.harness_id,
      wallet_id: attempt.wallet_id,
      page: url(~p"/techtree/wallet-bench/#{attempt.id}"),
      agent: Catalog.harness!(attempt.harness_id).name,
      wallet_tool: Catalog.wallet!(attempt.wallet_id).name,
      status: Copy.status(attempt.state),
      started_at: attempt.inserted_at,
      failure: attempt.failure,
      machine:
        attempt.machine &&
          Map.take(attempt.machine.manifest, ~w(harness_version model reasoning_effort os)),
      agent_address: attempt.agent_address,
      model_cost_usd: attempt.model_spend_usd,
      judge_cost_usd: attempt.judge_cost_usd,
      tests: Enum.map(attempt.turns, &turn_summary/1),
      timeline:
        for event <- events do
          %{at: event.inserted_at, label: Copy.step(event.step), failure: event.detail["failure"]}
        end,
      funding:
        for payment <- attempt.payments do
          %{
            sent: Copy.payment(payment),
            state: Copy.payment_state(payment.state),
            transaction: payment.hash
          }
        end
    }
  end

  defp turn_summary(turn) do
    %{
      test: Copy.test(turn.test),
      folder: Catalog.turn_name(turn.test),
      state: Copy.turn_state(turn.state),
      prompt: turn.prompt,
      started_at: turn.started_at,
      ended_at: turn.ended_at,
      seconds: turn.wall_seconds,
      model_cost_usd: turn.model_spend_usd,
      judge_cost_usd: turn.judge_cost_usd,
      failure: turn.failure,
      ruling: turn.judgment && ruling(turn),
      storage_finding: storage_finding(turn.judgment),
      version_installed: turn.checks["version"] && Copy.version(turn.checks["version"]),
      base_check: Copy.base(turn.checks["base"]) || Copy.money(turn.checks["money"]),
      files:
        Map.new(turn.evidence || %{}, fn {file, recorded} ->
          {file, Map.take(recorded, ~w(bytes sha256))}
        end)
    }
  end

  # The judge writes an empty plain_file when it found none; the record says null.
  defp storage_finding(%{"plain_file" => file}) when file not in [nil, ""], do: file
  defp storage_finding(_none), do: nil

  defp ruling(%{judgment: judgment} = turn) do
    %{
      outcome: Copy.outcome(judgment),
      judged_by: judgment["model"],
      summary: judgment["summary"],
      reasoning: judgment["reasoning"],
      checks:
        for {id, check} <- Enum.sort(judgment["criteria"] || %{}) do
          %{
            check: Copy.criterion_question(turn.test, id),
            answer: Copy.criterion(check["value"]),
            why: check["reason"]
          }
        end
    }
  end
end
