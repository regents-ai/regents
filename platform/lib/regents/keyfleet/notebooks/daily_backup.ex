defmodule Regents.Keyfleet.Notebooks.DailyBackup do
  @moduledoc """
  Once a day (`config :regents, Oban, cron:`): queues the copy of every
  changed notebook for each fleet with a notebook hub
  (`Regents.Keyfleet.Notebooks.Backups`), and removes copies kept longer than 90 days.
  """
  use Oban.Worker, queue: :keyfleet_default, max_attempts: 3

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.{Backup, Backups}

  @kept_days 90

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(Notebooks.hub_fleet_ids(), &Oban.insert!(Backups.new(%{fleet_id: &1})))

    Backup
    |> Ash.Query.for_read(
      :older_than,
      %{before: DateTime.add(DateTime.utc_now(), -@kept_days, :day)},
      actor: %System{}
    )
    |> Ash.bulk_destroy!(:forget, %{}, actor: %System{}, strategy: :atomic, notify?: false)

    :ok
  end
end
