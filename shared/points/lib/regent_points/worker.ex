defmodule RegentPoints.Worker do
  @moduledoc """
  Awards one recorded event under its account's lock, once its source, asked again
  there, still accepts it for the same account; a source that refuses, or now names
  another account, ends the event rejected as `award_refused`. Oban owns retries.
  When the last attempt fails, by an error or a raise, the event is rejected as
  `award_failed`, so the account's summary never counts it as pending forever, and
  the job keeps the failure. A last attempt killed outright (its node stopped) is
  discarded by Oban's Lifeline and leaves the event pending.

  A run is unique only while it waits: an event offered again once its award was
  refused gets its own run even while the run that refused it is still finishing.
  Two runs for one event are safe: each reads the event again under the account's
  lock and changes it only while it is still pending.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 10,
    unique: [
      keys: [:event_id],
      period: :infinity,
      states: [:suspended, :available, :scheduled, :retryable]
    ]

  alias RegentPoints.{Account, Store}

  @impl true
  def perform(%Oban.Job{args: %{"event_id" => id}} = job) do
    if job.attempt < job.max_attempts, do: award(id), else: last_attempt(id)
  end

  defp award(id) do
    with {:ok, _} <- RegentPoints.process_event(id, actor: Store.system()), do: :ok
  end

  defp last_attempt(id) do
    case award(id) do
      :ok -> :ok
      {:error, reason} -> give_up(id, reason)
    end
  rescue
    error -> give_up(id, error)
  end

  defp give_up(id, reason) do
    with %{processing_status: :pending, account_id: account} <- Store.event(id) do
      Ash.transact(Account, fn ->
        Store.lock_account(account)

        with %{processing_status: :pending, account_id: ^account} = event <- Store.event(id) do
          RegentPoints.finish_event!(
            event,
            %{processing_status: :rejected, reason_code: "award_failed"},
            actor: Store.system()
          )
        end
      end)
    end

    {:error, reason}
  end
end
