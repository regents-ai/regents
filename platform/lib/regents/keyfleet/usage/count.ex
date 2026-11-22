defmodule Regents.Keyfleet.Usage.Count do
  @moduledoc """
  Every hour (`config :regents, Oban, cron:`): counts each fleet's usage in
  the month under way and in the month before it (`Regents.Keyfleet.Usage.Month`),
  in place of their last counts, then queues a read of each notebook hub
  that counts its fleet's notebook hours (`Regents.Keyfleet.Usage.ReadHub`). The
  month before is counted again so the hour between a month's last count and
  its end is never left out, and a run that missed is made up by the next.
  Counting a month again gives the same figures while its records have not
  changed.
  """
  use Oban.Worker, queue: :keyfleet_default, max_attempts: 1

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.{Notebooks, Usage}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    this_month = Date.beginning_of_month(Date.utc_today())

    for fleet_id <- Regents.Keyfleet.Fleets.catalog_ids(),
        month <- [Date.shift(this_month, month: -1), this_month],
        do: Usage.count_month!(fleet_id, month, actor: %System{})

    Enum.each(Notebooks.hub_fleet_ids(), &Oban.insert!(Usage.ReadHub.new(%{fleet_id: &1})))

    :ok
  end
end
