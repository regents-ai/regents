defmodule Regents.Patchbay.Forum.EscrowRevenuePush do
  @moduledoc """
  Pushes the escrow's accumulated fees to REGENT staking after a bounty settles.
  The AshOban job stores its transaction hash and releases the fee queue while
  Base confirms it. Other fee jobs wait for a recorded push before sending.
  """

  use Ash.Resource.ManualUpdate

  import Ecto.Query, only: [from: 2]

  alias AshOban.Errors.SnoozeJob
  alias Regents.Account.Actors.System
  alias Regents.Patchbay.{Escrow, Forum}
  alias Regents.Repo

  @hash_key "escrow_revenue_tx_hash"
  @active_states ~w(available scheduled executing retryable)

  @impl true
  def update(%{context: %{ash_oban: %{job: %Oban.Job{} = job}}, data: report}, _opts, _context) do
    with :ok <- payout_landed(report), do: advance(report, job, job.meta[@hash_key])
  end

  def update(_changeset, _opts, _context), do: {:error, :fee_job_required}

  defp payout_landed(%{escrow_status: status} = report) do
    case Escrow.post(report.id) do
      {:ok, %{status: ^status}} -> :ok
      {:ok, _post} -> snooze()
      {:error, reason} -> {:error, reason}
    end
  end

  defp advance(report, job, hash) when is_binary(hash) do
    case Escrow.outcome(hash) do
      {:ok, :succeeded} ->
        with {:ok, _job} <- remember(job, nil), do: mark_pushed(report)

      {:ok, :reverted} ->
        with {:ok, _job} <- remember(job, nil), do: {:error, :push_reverted}

      {:error, _unconfirmed} ->
        snooze()
    end
  end

  defp advance(report, job, nil) do
    # Queue limits are per runner. The database lock also serializes the
    # brief send across nodes, until the job has recorded its hash.
    case Repo.transaction(fn -> push_if_unlocked(report, job) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp push_if_unlocked(report, job) do
    %{rows: [[locked?]]} =
      Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))", [
        "patchbay-escrow-revenue"
      ])

    if locked? and not another_push?(job), do: push_if_needed(report, job), else: snooze()
  end

  defp push_if_needed(report, job) do
    case Escrow.revenue_owed() do
      {:ok, 0} ->
        mark_pushed(report)

      {:ok, _kept} ->
        with {:ok, hash} <- Escrow.push_revenue(),
             {:ok, _job} <- remember(job, hash),
             do: snooze()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp another_push?(%Oban.Job{id: job_id, worker: worker}) do
    %{repo: repo, prefix: prefix} = Oban.config()

    waiting =
      from job in Oban.Job,
        where:
          job.worker == ^worker and job.id != ^job_id and job.state in ^@active_states and
            fragment("? ->> ? IS NOT NULL", job.meta, ^@hash_key)

    repo.exists?(waiting, prefix: prefix)
  end

  defp remember(job, nil), do: Oban.update_job(job, meta: Map.delete(job.meta, @hash_key))
  defp remember(job, hash), do: Oban.update_job(job, meta: Map.put(job.meta, @hash_key, hash))

  defp mark_pushed(report), do: Forum.record_escrow_revenue_pushed(report, actor: %System{})

  defp snooze, do: {:error, SnoozeJob.exception(snooze_for: 15)}
end
