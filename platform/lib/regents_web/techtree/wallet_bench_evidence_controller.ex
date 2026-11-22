defmodule RegentsWeb.Techtree.WalletBenchEvidenceController do
  @moduledoc """
  One recorded file of a wallet test, as plain text; the whole test as a zip;
  and the test's record on its own as JSON.

  Only a file the turn recorded is served: the turn and file names are looked
  up in the turn's own list, never used as a path, and the bytes read back
  must match the fingerprint recorded with them (`Regents.Techtree.WalletBench.Evidence.recorded/2`).

  When the database can't be read (`RegentsWeb.Techtree.Outage`) each answers 503
  asking to try again, never a 500 or a 404.
  """

  use RegentsWeb, :controller

  alias Regents.Techtree.WalletBench
  alias Regents.Techtree.WalletBench.{Catalog, Evidence}
  alias RegentsWeb.Techtree.{ExactResponse, Outage, ResultsUnreadableError}
  alias RegentsWeb.Techtree.WalletBenchCopy, as: Copy

  @load [:machine, :turns, :payments, :model_spend_usd, :judge_cost_usd]
  @downloads 4

  # sobelow_skip ["XSS.SendResp"]
  def show(conn, %{"id" => id, "turn" => turn_name, "file" => file}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, %{} = attempt} <-
           Outage.read(fn ->
             WalletBench.get_attempt!(id, load: [:turns], not_found_error?: false)
           end),
         %{evidence: %{^file => _recorded}} = turn <-
           Enum.find(attempt.turns, &(Catalog.turn_name(&1.test) == turn_name)) do
      with_download_place(conn, fn -> send_recorded(conn, turn, file) end)
    else
      :database_down -> busy(conn)
      _missing -> raise RegentsWeb.NotFoundError, "no recorded file has that name"
    end
  end

  defp send_recorded(conn, turn, file) do
    case Evidence.recorded(turn, file) do
      {:ok, body} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, body)

      {:error, reason} ->
        unread(conn, reason)
    end
  end

  @doc """
  The whole test as one zip, written as it is sent: `results.json` then every
  file each test recorded, under its test's name.
  """
  def results(conn, %{"id" => id}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, {attempt, events}} <- Outage.read(fn -> read(id) end) do
      with_download_place(conn, fn -> send_results(conn, attempt, events) end)
    else
      :database_down -> busy(conn)
      _missing -> raise RegentsWeb.NotFoundError, "no wallet test has that number"
    end
  end

  defp with_download_place(conn, send) do
    {:ok, _owner} = Registry.register(RegentsWeb.Techtree.ResultsDownloads, :download, nil)

    if Registry.count_match(RegentsWeb.Techtree.ResultsDownloads, :download, :_) > @downloads do
      Registry.unregister(RegentsWeb.Techtree.ResultsDownloads, :download)
      busy(conn)
    else
      try do
        send.()
      after
        Registry.unregister(RegentsWeb.Techtree.ResultsDownloads, :download)
      end
    end
  end

  defp unread(conn, %Req.TransportError{}), do: busy(conn)
  defp unread(conn, {:evidence, status}) when status == 429 or status >= 500, do: busy(conn)
  defp unread(_conn, reason), do: raise(ResultsUnreadableError, inspect(reason))

  defp busy(conn) do
    conn
    |> put_resp_header("retry-after", "30")
    |> put_status(503)
    |> put_root_layout(false)
    |> put_view(html: RegentsWeb.ErrorHTML)
    |> render(:"503")
  end

  defp send_results(conn, attempt, events) do
    files =
      for turn <- attempt.turns,
          file <- Enum.sort(Map.keys(turn.evidence || %{})),
          do: {turn, file}

    case Enum.find_value(files, &unchecked/1) do
      nil -> send_zip(conn, attempt, events, files)
      {:error, reason} -> unread(conn, reason)
    end
  end

  defp unchecked({turn, file}) do
    with :ok <- Evidence.check(turn, file), do: nil
  end

  defp send_zip(conn, attempt, events, files) do
    folder = "wallet-test-#{String.slice(attempt.id, 0, 8)}"
    mtime = attempt.inserted_at

    entries =
      for {turn, file} <- files do
        Zstream.entry(
          "#{folder}/#{Catalog.turn_name(turn.test)}/#{file}",
          Stream.map([file], &recorded!(turn, &1)),
          mtime: mtime
        )
      end

    results =
      Zstream.entry(
        "#{folder}/results.json",
        [Jason.encode!(record(attempt, events), pretty: true)],
        mtime: mtime
      )

    conn
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{folder}.zip"))
    |> put_resp_content_type("application/zip", nil)
    |> send_chunked(200)
    |> send_stream(Zstream.zip([results | entries]))
  end

  defp send_stream(conn, stream) do
    Enum.reduce_while(stream, conn, fn data, conn ->
      case chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, _gone} -> {:halt, conn}
      end
    end)
  end

  defp recorded!(turn, file) do
    case Evidence.recorded(turn, file) do
      {:ok, body} -> body
      {:error, reason} -> raise "A recorded file can't be read: #{inspect(reason)}"
    end
  end

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
