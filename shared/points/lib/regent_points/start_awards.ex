defmodule RegentPoints.StartAwards do
  @moduledoc """
  Gives the one-time points for what an account has that Points has not recorded
  yet: the account, its linked X, GitHub and Farcaster accounts and its first
  paired agent (`RegentPoints.Rules.start_rules/0`), at most 80 points, without the
  person doing anything. What it had before the start earns at the start time;
  what came after the start earns at its real time, such as an account that joined
  after the start but before its site turned Points on.

  Every site with a start-rule source runs it from an hourly cron line. With no
  start time, before the start, and after the last season's end, it stops; the
  first hourly run after the start does the work. From the start it asks each
  approved start rule's source,
  `existing(rule_id, now)` with the run's own time, for what is there now, one
  `{account_id, reference}` per account, and records it through
  `RegentPoints.record_event/2` like any action, so the source still proves it and
  an account earns each rule once whichever site records it. Its offers carry
  `start_run: true`, so their checks and awards wait behind live ones, and an offer
  whose check is still waiting from an earlier run is that same job. The accounts
  whose event for the rule earned or was capped are read once per rule and left
  out. An account whose event was refused is offered again, and so is one whose
  event still waits: its check finds the waiting event and queues its award, which
  is one job while it waits.

  Unique for a day while it waits, runs or has succeeded, so once a run succeeds
  no other runs that day; a run that ends cancelled or discarded lets the next
  hourly line start another. Each run records what no listener has.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 5,
    unique: [period: {1, :day}, states: :successful]

  require Ash.Query
  alias RegentPoints.{Event, Rules, Store}

  @impl true
  def perform(_job) do
    now = DateTime.utc_now()

    start = Keyword.get(Rules.config(), :starts_at)

    cond do
      start == nil or DateTime.before?(now, start) -> {:cancel, :not_started}
      not DateTime.before?(now, Rules.ends_at()) -> {:cancel, :ended}
      true -> record_all(now)
    end
  end

  defp record_all(now) do
    for id <- Rules.start_rules(), Rules.enabled?(id), do: record_existing(id, now)
    :ok
  end

  defp record_existing(id, now) do
    recorded = recorded(id)

    for {account_id, reference} <- Rules.adapter(id).existing(id, now),
        not MapSet.member?(recorded, account_id) do
      {:ok, _} =
        RegentPoints.record_event(Map.put(reference, :rule_id, id), %{start_run: true},
          actor: Store.system()
        )
    end
  end

  defp recorded(rule_id) do
    Event
    |> Ash.Query.filter(
      program_id == ^Rules.program() and rule_id == ^rule_id and
        processing_status in [:confirmed, :capped]
    )
    |> Ash.Query.select([:account_id])
    |> Ash.Query.distinct([:account_id])
    |> Ash.read!(actor: Store.system())
    |> MapSet.new(& &1.account_id)
  end
end
