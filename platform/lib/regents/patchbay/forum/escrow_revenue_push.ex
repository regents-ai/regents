defmodule Regents.Patchbay.Forum.EscrowRevenuePush do
  @moduledoc """
  Pushes escrow fees to REGENT staking after a bounty settles. The job
  records its signed transaction before broadcast and retries those same
  bytes while the receipt is pending.
  """

  use Ash.Resource.ManualUpdate

  import Ecto.Query, only: [from: 2]

  alias AshOban.Errors.SnoozeJob
  alias Regents.Account.Actors.System, as: SystemActor
  alias Regents.Patchbay.{Escrow, Forum}
  alias Regents.Repo

  @hash_key "escrow_revenue_tx_hash"
  @raw_key "escrow_revenue_raw_transaction"
  @deadline_key "escrow_revenue_receipt_deadline"
  @receipt_window_seconds 300
  @active_states ~w(available scheduled executing retryable)

  @impl true
  def update(%{context: %{ash_oban: %{job: %Oban.Job{} = job}}, data: report}, _opts, _context) do
    with :ok <- payout_landed(report), do: advance(report, job, job.meta[@hash_key])
  end

  def update(_changeset, _opts, _context), do: {:error, :fee_job_required}

  defp payout_landed(%{escrow_status: status} = report) do
    case Escrow.post(report.id) do
      {:ok, %{status: ^status}} -> :ok
      {:ok, _post} -> {:error, :payout_unconfirmed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp advance(report, job, hash) when is_binary(hash) do
    case Escrow.outcome(hash) do
      {:ok, :succeeded} ->
        with {:ok, _job} <- forget(job), do: mark_pushed(report)

      {:ok, :reverted} ->
        with {:ok, _job} <- forget(job), do: {:error, :push_reverted}

      {:error, :not_landed} ->
        wait_for_push(job)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp advance(report, job, nil) do
    case Escrow.revenue_owed() do
      {:ok, 0} -> mark_pushed(report)
      {:ok, _kept} -> prepare(job)
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare(job) do
    with false <- another_push?(job),
         {:ok, transaction} <- Escrow.prepare_revenue_push(),
         {:ok, saved} <- reserve(job, transaction) do
      broadcast(saved)
    else
      true -> snooze()
      {:error, reason} -> {:error, reason}
    end
  end

  defp wait_for_push(job) do
    if job.meta[@deadline_key] && job.meta[@deadline_key] > System.os_time(:second),
      do: broadcast(job),
      else: {:error, :push_confirmation_timed_out}
  end

  # Only the database reservation is locked. Signing, sending and receipt
  # reads all run outside this transaction.
  defp reserve(job, transaction) do
    with {:ok, result} <- Repo.transaction(fn -> reserve_if_unlocked(job, transaction) end),
         do: result
  end

  defp reserve_if_unlocked(job, transaction) do
    %{rows: [[locked?]]} =
      Repo.query!("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))", [
        "patchbay-escrow-revenue"
      ])

    if locked? and not another_push?(job) do
      meta =
        Map.merge(job.meta, %{
          @hash_key => transaction.hash,
          @raw_key => transaction.raw,
          @deadline_key => System.os_time(:second) + @receipt_window_seconds
        })

      Oban.update_job(job, %{meta: meta})
    else
      snooze()
    end
  end

  defp another_push?(%Oban.Job{id: job_id, worker: worker}) do
    %{repo: repo, prefix: prefix} = Oban.config()
    now = System.os_time(:second)

    waiting =
      from job in Oban.Job,
        where:
          job.worker == ^worker and job.id != ^job_id and job.state in ^@active_states and
            fragment("(? ->> ?)::bigint > ?", job.meta, ^@deadline_key, ^now)

    repo.exists?(waiting, prefix: prefix)
  end

  defp broadcast(job) do
    case Escrow.broadcast_revenue_push(job.meta[@raw_key]) do
      :ok -> snooze()
      {:error, reason} -> {:error, reason}
    end
  end

  defp forget(job),
    do: Oban.update_job(job, %{meta: Map.drop(job.meta, [@hash_key, @raw_key, @deadline_key])})

  defp mark_pushed(report), do: Forum.record_escrow_revenue_pushed(report, actor: %SystemActor{})

  defp snooze, do: {:error, SnoozeJob.exception(snooze_for: 15)}
end
