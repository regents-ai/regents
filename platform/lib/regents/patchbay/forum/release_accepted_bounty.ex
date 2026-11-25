defmodule Regents.Patchbay.Forum.ReleaseAcceptedBounty do
  @moduledoc """
  Pays the accepted answer from escrow. The accept action queues the report,
  reply and the author’s wallet together. Base owns the terminal state, so a
  retry first reads the contract and checks a submitted receipt before sending.
  """

  use Oban.Worker,
    queue: :patchbay_fees,
    max_attempts: 15,
    unique: [keys: [:report_id], period: :infinity, states: :incomplete]

  alias Regents.Patchbay.Escrow
  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.{PriorityRefund, Report}

  @system %Regents.Account.Actors.System{}
  @held [:credited, :refund_failed, :release_failed, :release_submitted]

  def new_payout(%Report{accepted_reply: reply} = report) do
    new(%{report_id: report.id, reply_id: reply.id, wallet: reply.author.wallet_address})
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"report_id" => id, "reply_id" => reply_id, "wallet" => wallet}} = job
      ) do
    case pay(id, reply_id, wallet) do
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

  defp pay(id, reply_id, wallet) do
    with {:ok, %Report{accepted_reply_id: ^reply_id} = report} <-
           Forum.get_report(id, actor: @system),
         :ok <- ready(report),
         {:ok, post} <- Escrow.post(id) do
      advance(report, post, wallet)
    else
      {:ok, _missing} -> {:cancel, :accepted_reply_missing}
      other -> other
    end
  end

  defp ready(%Report{escrow_status: state}) when state in @held, do: :ok
  defp ready(%Report{escrow_status: :credit_submitted}), do: {:error, :credit_unconfirmed}
  defp ready(_report), do: {:cancel, :bounty_not_held}

  defp advance(report, %{status: :released}, _wallet),
    do: record(report, :released, :keep)

  defp advance(report, %{status: :refunded}, _wallet) do
    case PriorityRefund.record(report, nil) do
      {:ok, _report} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp advance(%Report{escrow_release_tx_hash: hash} = report, %{status: :funded}, _wallet)
       when is_binary(hash) do
    case Escrow.outcome(hash) do
      {:ok, :succeeded} ->
        record(report, :released, hash)

      {:ok, :reverted} ->
        with :ok <- record(report, :release_failed, nil), do: {:error, :release_reverted}

      {:error, :not_landed} ->
        {:error, :release_unconfirmed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp advance(report, %{status: :funded}, wallet) do
    with {:ok, hash} <- Escrow.release(report.id, wallet),
         :ok <- record(report, :release_submitted, hash) do
      {:snooze, 10}
    end
  end

  defp advance(_report, _post, _wallet), do: {:error, :escrow_unconfirmed}

  defp record(report, status, hash) do
    case update_release(report.id, report.accepted_reply_id, status, hash) do
      {:ok, _report} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_release(id, reply_id, status, hash) do
    case Ash.transact([Report], fn -> record_current(id, reply_id, status, hash) end) do
      {:ok, {:ok, report}} -> {:ok, report}
      {:error, reason} -> {:error, reason}
    end
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
