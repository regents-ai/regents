defmodule Regents.Patchbay.Forum.EscrowRevenuePush do
  @moduledoc """
  Pushes escrow fees to REGENT staking after a bounty settles. The job
  records its signed transaction before broadcast and retries those same
  bytes for five minutes. After that it keeps the hash and only reads for
  confirmation, so a second push cannot replace an unresolved transaction.
  """

  use Ash.Resource.ManualUpdate

  import Ecto.Query, only: [from: 2]
  require Logger

  alias AshOban.Errors.SnoozeJob
  alias Regents.Account.Actors.System, as: SystemActor
  alias Regents.Patchbay.{Escrow, Forum}
  alias Regents.Repo

  @hash_key "escrow_revenue_tx_hash"
  @raw_key "escrow_revenue_raw_transaction"
  @deadline_key "escrow_revenue_receipt_deadline"
  @receipt_window_seconds 300
  @receipt_recheck_seconds 60
  @unresolved_states ~w(available scheduled executing retryable discarded cancelled)

  @impl true
  def update(%{context: %{ash_oban: %{job: %Oban.Job{} = job}}, data: report}, _opts, _context) do
    advance(report, job, job.meta[@hash_key])
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
        finish(report, job)

      {:ok, :reverted} ->
        with {:ok, _job} <- forget(job), do: {:error, :push_reverted}

      {:error, :not_landed} ->
        wait_for_push(job, true)

      {:error, _unread} ->
        wait_for_push(job, false)
    end
  end

  defp advance(report, job, nil) do
    with :ok <- payout_landed(report) do
      read_revenue(report, job)
    end
  end

  defp finish(report, job) do
    Repo.transact(fn ->
      with {:ok, pushed} <- mark_pushed(report),
           {:ok, _job} <- forget(job),
           do: {:ok, pushed}
    end)
  end

  defp read_revenue(report, job) do
    case Escrow.revenue_owed() do
      {:ok, 0} -> mark_pushed(report)
      {:ok, _kept} -> prepare(job)
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare(job) do
    with :ok <- wait_for_other_push(job),
         {:ok, transaction} <- Escrow.prepare_revenue_push(),
         {:ok, saved} <- reserve(job, transaction) do
      broadcast(saved)
    end
  end

  defp wait_for_other_push(job) do
    case unresolved_push(job) do
      %{id: id, state: "discarded"} ->
        with :ok <- Oban.retry_job(id), do: snooze()

      %{} ->
        snooze()

      nil ->
        :ok
    end
  end

  defp wait_for_push(job, broadcast?) do
    case job.meta[@deadline_key] do
      deadline when is_integer(deadline) ->
        cond do
          deadline <= System.os_time(:second) -> await_receipt(job)
          broadcast? -> broadcast(job)
          true -> snooze()
        end

      _receipt_only ->
        snooze(@receipt_recheck_seconds)
    end
  end

  defp await_receipt(job) do
    with {:ok, _job} <-
           Oban.update_job(job, %{meta: Map.drop(job.meta, [@raw_key, @deadline_key])}) do
      Logger.warning(
        "Patchbay fee push job #{job.id} is awaiting a receipt after its broadcast window"
      )

      snooze(@receipt_recheck_seconds)
    end
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

    if locked? and is_nil(unresolved_push(job)) do
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

  defp unresolved_push(%Oban.Job{id: job_id, worker: worker}) do
    %{repo: repo, prefix: prefix} = Oban.config()

    waiting =
      from job in Oban.Job,
        where:
          job.worker == ^worker and job.id != ^job_id and job.state in ^@unresolved_states and
            fragment("? ->> ? IS NOT NULL", job.meta, ^@hash_key),
        order_by: job.id,
        limit: 1,
        select: %{id: job.id, state: job.state}

    repo.one(waiting, prefix: prefix)
  end

  defp broadcast(job) do
    case Escrow.broadcast_signed(job.meta[@raw_key]) do
      :ok -> snooze()
      {:error, :broadcast_unconfirmed} -> snooze()
      {:error, reason} -> {:error, reason}
    end
  end

  defp forget(job),
    do: Oban.update_job(job, %{meta: Map.drop(job.meta, [@hash_key, @raw_key, @deadline_key])})

  defp mark_pushed(report), do: Forum.record_escrow_revenue_pushed(report, actor: %SystemActor{})

  defp snooze(seconds \\ 15), do: {:error, SnoozeJob.exception(snooze_for: seconds)}
end
