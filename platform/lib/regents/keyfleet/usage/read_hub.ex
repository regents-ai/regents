defmodule Regents.Keyfleet.Usage.ReadHub do
  @moduledoc """
  Reads the notebook machines one fleet's hub lists (`Regents.Keyfleet.Usage.Machine`)
  and counts the fleet's notebook hours from them (`Regents.Keyfleet.Usage.Month`),
  queued every hour by `Regents.Keyfleet.Usage.Count` once it has counted the month.

  The month under way is counted each time. The month before is counted
  again only once it has a figure, so a month that ended before the hub was
  first read stays without one: its machines were never seen.

  A hub that does not answer is asked again five minutes later, six times
  at most (`Regents.Keyfleet.Notebooks.HubClient.wait_while_away/2`), saving
  nothing meanwhile, so a hub restarting for a deploy goes unremarked; one
  still away after that ends the read as a failed job. A hub that answers
  with a refusal ends it at once. A failed read is not tried again: the
  next hour's read records everything it would have, as long as the hub
  still holds it (`Regents.Keyfleet.Usage.Machine`).

  It waits its turn with the other hub calls (the `keyfleet_notebook_hubs` queue runs
  one job), and a fleet's read is queued again only once the last has run,
  so the hour's read is never queued beside one still waiting for its hub.
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_hubs,
    max_attempts: 1,
    unique: [keys: [:fleet_id], period: :infinity, states: :incomplete]

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Notebooks.HubClient
  alias Regents.Keyfleet.Usage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fleet_id" => fleet_id}} = job) do
    case HubClient.machines(fleet_id) do
      {:ok, machines} -> record(fleet_id, machines)
      failed -> HubClient.wait_while_away(failed, job)
    end
  end

  defp record(fleet_id, machines) do
    seen_at = DateTime.utc_now()

    machines
    |> Enum.map(
      &(&1
        |> Map.take(["id", "kind", "started_at", "ended_at"])
        |> Map.merge(%{"fleet_id" => fleet_id, "seen_at" => seen_at}))
    )
    |> Usage.record_machines!(actor: %System{})

    this_month = Date.beginning_of_month(Date.utc_today())

    for month <- [Date.shift(this_month, month: -1), this_month],
        %Usage.Month{} = usage <- [Usage.month_usage!(fleet_id, month)],
        month == this_month or usage.notebook_seconds != nil,
        do: Usage.count_notebooks!(usage, actor: %System{})

    :ok
  end
end
