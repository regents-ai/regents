defmodule Regents.Keyfleet.Seasons.Turns do
  @moduledoc """
  Every ten minutes, from a minute past each hour (`config :regents, Oban,
  cron:`): queues a `Regents.Keyfleet.Seasons.Turn` for each deployed fleet at the
  season boundary last passed. While a fleet's turn at that boundary is waiting
  or running it is not queued again; once it has finished it is, so a turn that
  ran out of attempts is tried again within ten minutes, and one that succeeded
  runs again and changes nothing.
  """
  use Oban.Worker, queue: :keyfleet_default, max_attempts: 1

  alias Regents.Keyfleet.Seasons
  alias Regents.Keyfleet.Seasons.Turn

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    if Regents.ProductActivity.cron_allowed?(:keyfleet, job) do
      boundary = DateTime.utc_now() |> Seasons.boundary() |> DateTime.to_iso8601()

      Enum.each(
        Regents.Keyfleet.Fleets.list_deployed_fleets!(),
        &Oban.insert!(Turn.new(%{fleet_id: &1.id, boundary: boundary}))
      )
    end

    :ok
  end
end
