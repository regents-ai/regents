defmodule Regents.Patchbay.Forum.ReleaseAcceptedBounty do
  @moduledoc """
  Pays the accepted answer from escrow. The accept action queues the report,
  reply and the author’s wallet together. The signed bytes and hash are saved
  before broadcast. Retries check Base and may rebroadcast only those bytes
  while the result is unknown.
  """

  use Oban.Worker,
    queue: :patchbay_fees,
    max_attempts: 15,
    unique: [keys: [:report_id], period: :infinity, states: :incomplete]

  import Ecto.Query
  require Logger

  alias Regents.Patchbay.Escrow
  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.{PriorityRefund, Report}
  alias Regents.Repo

  @system %Regents.Account.Actors.System{}
  @held [:credited, :refund_failed, :release_failed, :release_submitted]
  @raw_key "escrow_release_raw_transaction"
  @deadline_key "escrow_release_broadcast_deadline"
  @recovered_key "escrow_release_recovered"
  @broadcast_window_seconds 300

  def new_payout(%Report{accepted_reply: reply} = report) do
    new(%{report_id: report.id, reply_id: reply.id, wallet: reply.author.wallet_address})
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"report_id" => id, "reply_id" => reply_id, "wallet" => wallet}} = job
      ) do
    case pay(id, reply_id, wallet, job) do
      {:error, reason} = error when job.attempt >= job.max_attempts ->
        case update_release(id, reply_id, :release_failed, :keep) do
          {:ok, _report} -> error
          {:error, update_error} -> {:error, {:release_failed, reason, update_error}}
        end

      result ->
        result
    end
  end

  @doc "Records a payout the escrow watcher saw confirmed on Base."
  def record_confirmation(%Report{accepted_reply_id: reply_id} = report) when is_binary(reply_id),
    do: update_release(report.id, reply_id, :released, :keep)

  @doc "Wakes the original payout for an older acceptance once its credit is confirmed."
  def resume_after_credit(%Report{accepted_reply_id: reply_id} = report)
      when is_binary(reply_id) do
    case payout_job(report) do
      %Oban.Job{state: state} = job when state in ["cancelled", "discarded"] ->
        with :ok <- Oban.retry_job(job), do: {:ok, report}

      nil ->
        Logger.warning("Accepted Patchbay bounty #{report.id} has no retained payout job")
        Forum.record_escrow_release(report, %{escrow_status: :release_failed}, actor: @system)

      _job ->
        {:ok, report}
    end
  end

  def resume_after_credit(%Report{} = report), do: {:ok, report}

  @doc "Retries the original discarded payout only after its transaction is known to have reverted."
  def retry_reverted(%Report{escrow_release_tx_hash: hash} = report) when is_binary(hash) do
    case Escrow.outcome(hash) do
      {:ok, :reverted} ->
        Repo.transact(fn -> retry_discarded(report, hash) end)

      _unresolved ->
        {:ok, report}
    end
  end

  def retry_reverted(%Report{} = report), do: {:ok, report}

  defp retry_discarded(report, hash) do
    with {:ok, %Report{escrow_status: :release_failed, escrow_release_tx_hash: ^hash} = current} <-
           Forum.lock_report(report.id, actor: @system),
         %Oban.Job{state: "discarded", meta: meta} = job <- payout_job(current),
         false <- Map.get(meta, @recovered_key, false),
         {:ok, updated} <-
           Forum.record_escrow_release(
             current,
             %{escrow_status: :release_failed, escrow_release_tx_hash: nil},
             actor: @system
           ),
         {:ok, job} <- Oban.update_job(job, %{meta: Map.put(meta, @recovered_key, true)}),
         :ok <- Oban.retry_job(job) do
      {:ok, updated}
    else
      {:error, _reason} = error -> error
      _changed_or_no_job -> {:ok, report}
    end
  end

  defp payout_job(%Report{id: id, accepted_reply_id: reply_id}) do
    %{repo: repo, prefix: prefix} = Oban.config()
    worker = Oban.Worker.to_string(__MODULE__)

    from(job in Oban.Job,
      where:
        job.worker == ^worker and
          fragment("? @> ?", job.args, ^%{"report_id" => id, "reply_id" => reply_id}),
      order_by: [desc: job.id],
      limit: 1
    )
    |> repo.one(prefix: prefix)
  end

  defp pay(id, reply_id, wallet, job) do
    with {:ok, %Report{accepted_reply_id: ^reply_id} = report} <-
           Forum.get_report(id, actor: @system),
         :ok <- ready(report),
         {:ok, post} <- Escrow.post(id) do
      advance(report, post, wallet, job)
    else
      {:ok, _missing} -> {:cancel, :accepted_reply_missing}
      other -> other
    end
  end

  defp ready(%Report{escrow_status: state}) when state in @held, do: :ok

  defp ready(%Report{escrow_status: state})
       when state in [nil, :credit_submitted, :credit_failed],
       do: {:snooze, 60}

  defp ready(_report), do: {:cancel, :bounty_not_held}

  defp advance(report, %{status: :released}, _wallet, _job),
    do: record(report, :released, :keep)

  defp advance(report, %{status: :refunded}, _wallet, _job) do
    case PriorityRefund.record(report, nil) do
      {:ok, _report} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp advance(%Report{escrow_release_tx_hash: hash} = report, %{status: :funded}, _wallet, job)
       when is_binary(hash) do
    case Escrow.outcome(hash) do
      {:ok, :succeeded} ->
        record(report, :released, hash)

      {:ok, :reverted} when job.attempt >= job.max_attempts ->
        {:error, :release_reverted}

      {:ok, :reverted} ->
        with :ok <- record(report, :release_failed, nil), do: {:error, :release_reverted}

      {:error, :not_landed} ->
        rebroadcast(job)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp advance(report, %{status: :funded}, wallet, job) do
    with {:ok, transaction} <- Escrow.prepare_release(report.id, wallet),
         {:ok, saved} <- save_submission(report, job, transaction) do
      rebroadcast(saved)
    end
  end

  defp advance(_report, _post, _wallet, _job), do: {:error, :escrow_unconfirmed}

  defp save_submission(report, job, transaction) do
    Repo.transact(fn ->
      with {:ok, %Report{escrow_release_tx_hash: nil, escrow_status: state} = current}
           when state in @held <- Forum.lock_report(report.id, actor: @system),
           true <- current.accepted_reply_id == report.accepted_reply_id,
           {:ok, _updated} <-
             Forum.record_escrow_release(
               current,
               %{escrow_status: :release_submitted, escrow_release_tx_hash: transaction.hash},
               actor: @system
             ) do
        meta =
          Map.merge(job.meta, %{
            @raw_key => transaction.raw,
            @deadline_key => System.os_time(:second) + @broadcast_window_seconds
          })

        Oban.update_job(job, %{meta: meta})
      else
        {:error, _reason} = error -> error
        _changed -> {:error, :payout_state_changed}
      end
    end)
  end

  defp rebroadcast(%Oban.Job{meta: %{@raw_key => raw, @deadline_key => deadline}})
       when is_integer(deadline) do
    if deadline > System.os_time(:second),
      do: broadcast(raw),
      else: {:error, :release_unconfirmed}
  end

  defp rebroadcast(_job), do: {:error, :release_unconfirmed}

  defp broadcast(raw) do
    case Escrow.broadcast_signed(raw) do
      :ok -> {:snooze, 10}
      {:error, :broadcast_unconfirmed} -> {:snooze, 10}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record(report, status, hash) do
    case update_release(report.id, report.accepted_reply_id, status, hash) do
      {:ok, _report} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_release(id, reply_id, status, hash) do
    Repo.transact(fn -> record_current(id, reply_id, status, hash) end)
  end

  defp record_current(id, reply_id, status, hash) do
    case Forum.lock_report(id, actor: @system) do
      {:ok, %Report{accepted_reply_id: ^reply_id, escrow_status: state} = current}
      when state in @held ->
        hash = if hash == :keep, do: current.escrow_release_tx_hash, else: hash

        Forum.record_escrow_release(
          current,
          %{escrow_status: status, escrow_release_tx_hash: hash},
          actor: @system
        )

      {:ok, closed} ->
        {:ok, closed}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
