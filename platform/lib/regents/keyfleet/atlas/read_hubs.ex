defmodule Regents.Keyfleet.Atlas.ReadHubs do
  @moduledoc """
  Every hour (`config :regents, Oban, cron:`): queues a read of each fleet's
  notebook hub for the Atlas (`Regents.Keyfleet.Atlas.ReadHub`).
  """
  use Oban.Worker, queue: :keyfleet_default, max_attempts: 1

  alias Regents.Keyfleet.Atlas.ReadHub
  alias Regents.Keyfleet.Notebooks

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(Notebooks.hub_fleet_ids(), &Oban.insert!(ReadHub.new(%{fleet_id: &1})))
    :ok
  end
end
