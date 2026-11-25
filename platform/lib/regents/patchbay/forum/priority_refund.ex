defmodule Regents.Patchbay.Forum.PriorityRefund do
  @moduledoc """
  Asking Base to take a bounty off the board and send it back to the asker who
  put it up.

  The escrow contract owns this rule, not Regents.Patchbay. It refuses a refund until
  thirty days after the money was recorded, and once that has passed it lets
  anybody make one, paying the asker 90% and keeping 10% for REGENT staking:
  the same split answering the question would have paid, so taking a bounty
  back is never the cheaper way out of it.

  Patchbay's part is only a relay for the asker's convenience, and it pays the
  gas, which is why it relays for the asker alone. Base accepting the
  transaction is the refund being sent; it has happened when the transaction's
  receipt says it succeeded (`Regents.Patchbay.Forum.RefundRelayRecord`). Nothing here decides whether
  the money can move. Every press reaches the chain, including a press before
  the thirty days and a second press while an earlier one is in flight, and
  what the chain says is written down. A press the chain refuses costs gas and
  changes nothing, which is an accepted outcome.
  """

  alias Regents.Patchbay.Escrow
  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.{RefundRelayRecord, Report}

  require Logger

  @system %Regents.Account.Actors.System{}

  @doc """
  Relays `actor`'s request to take the bounty on `report_id` back, and returns
  the report as it stands afterwards.
  """
  @spec run(String.t(), struct() | nil) :: {:ok, Report.t()} | {:error, term()}
  def run(report_id, actor) do
    with {:ok, uuid} <- uuid(report_id),
         {:ok, report} <- found_or_missing(Forum.get_report(uuid)),
         {:ok, asked} <- Forum.request_refund(report, actor: actor) do
      send_back(asked)
    end
  end

  @doc """
  Records a refund that has already happened on Base, whoever made it.

  This is how a refund Patchbay never relayed reaches the board, and how one it
  relayed does once its receipt says it succeeded.
  """
  @spec record(Report.t(), String.t() | nil) :: {:ok, Report.t()} | {:error, term()}
  def record(report, tx_hash) do
    update_current(report, fn
      %Report{escrow_status: :released} = current -> {:ok, current}
      current -> record_refund(current, :refunded, tx_hash || current.escrow_refund_tx_hash)
    end)
  end

  # Both the relay and the watcher use the row as it stands when writing the
  # result. A late refusal must leave a confirmed payout or refund intact.
  defp update_current(report, update) do
    case Ash.transact([Report], fn -> update_locked(report.id, update) end) do
      {:ok, {:ok, current}} -> {:ok, current}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_locked(id, update) do
    case Forum.lock_report(id, actor: @system) do
      {:ok, %Report{} = current} -> update.(current)
      {:ok, nil} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_refund(report, status, hash) do
    Forum.record_escrow_refund(
      report,
      %{escrow_status: status, escrow_refund_tx_hash: hash},
      actor: @system
    )
  end

  defp uuid(report_id) do
    case Ecto.UUID.cast(report_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end

  defp found_or_missing({:ok, nil}), do: {:error, :not_found}
  defp found_or_missing({:ok, record}), do: {:ok, record}

  defp found_or_missing({:error, error}) do
    if missing?(error), do: {:error, :not_found}, else: {:error, error}
  end

  @doc "Whether an error means there is no such report."
  @spec missing?(term()) :: boolean()
  def missing?(%Ash.Error.Query.NotFound{}), do: true
  def missing?(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &missing?/1)
  def missing?(_error), do: false

  # The money goes back to the payer the contract already recorded, so nothing
  # here says where it goes. The answer carries the transaction Base accepted,
  # whatever the database can write now; what became of it is written by a job
  # once its receipt is in (`RefundRelayRecord`). The watch still writes the
  # refund itself when it sees the money go back.
  defp send_back(asked) do
    case Escrow.refund(asked.id) do
      {:ok, tx_hash} ->
        queue_record(asked, tx_hash)
        {:ok, %{asked | escrow_refund_tx_hash: tx_hash}}

      {:error, _reason} ->
        refused(asked)
    end
  end

  # A database too busy to take even the job loses only the job: the watch
  # writes the refund down when it sees the money go back.
  defp queue_record(asked, tx_hash) do
    case Oban.insert(RefundRelayRecord.new_record(asked.id, tx_hash)) do
      {:ok, _job} ->
        :ok

      {:error, _reason} ->
        Logger.warning(
          "refund #{tx_hash} for report #{asked.id} was accepted by Base but not queued to be written down"
        )
    end
  end

  @doc """
  Records that Base refused a refund: when the transaction was handed over, or
  in its receipt afterwards.

  Only a bounty Base holds is written refused: one confirmed held, or one
  already refused before. Every other state is what Base last confirmed, and
  a refused press leaves it standing: a bounty not yet confirmed held would
  lose that confirmation, and one paid to the answer's author or refunded
  stays paid out. The asker's button reaches the chain in every state, so a
  press on a paid-out bounty is refused there and must not undo the payout.
  """
  @spec refused(Report.t()) :: {:ok, Report.t()} | {:error, term()}
  def refused(%Report{} = asked) do
    update_current(asked, fn
      %Report{escrow_status: status} = current when status in [:credited, :refund_failed] ->
        record_refund(current, :refund_failed, nil)

      current ->
        {:ok, current}
    end)
  end
end
