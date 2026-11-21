defmodule Regents.Keyfleet.Notebooks.Reconcile do
  @moduledoc """
  Every ten minutes (`config :regents, Oban, cron:`): queues a
  `Regents.Keyfleet.Notebooks.Roster` run for every fleet with a notebook hub, so a
  hub catches up with anything a run missed, such as a shard running out, and
  clears the "Open notebooks" links a day past their time.
  """
  use Oban.Worker, queue: :keyfleet_default, max_attempts: 3

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Notebooks

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(Notebooks.hub_fleet_ids(), &Oban.insert!(Notebooks.Roster.new(%{fleet_id: &1})))

    Notebooks.Handoff
    |> Ash.Query.for_read(:expired, %{}, actor: %System{})
    |> Ash.bulk_destroy!(:clear, %{}, actor: %System{}, strategy: :atomic, notify?: false)

    :ok
  end
end
