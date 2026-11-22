defmodule Regents.Keyfleet.Usage.Machine do
  @moduledoc """
  One notebook machine the fleet's hub started, as this site last read it from
  the hub's list of machines (`Regents.Keyfleet.Usage.ReadHub`): a `:session`
  machine, started for someone to open a notebook, or a `:run` machine,
  started for a notebook's background job. `id` is the hub's session or run
  id, `started_at` and `ended_at` the hub's, `seen_at` the last read that
  listed it.

  A machine counts from `started_at` until `ended_at`, or, while the hub has
  not said it ended, until `seen_at`. One whose end is never seen, because
  its record is gone from the hub before a read sees it end, stops counting
  at its last sighting, so its hours never run past what was seen and can be
  short by up to the hour between reads.

  What is not counted:

    * Machines the hub never lists: one it started that belongs to no
      session or run, a session that never got a machine, and a run that
      never started one.
    * Machines whose whole life falls in a gap in the hub reads longer than
      the hub keeps their record: about a day after a session ends, 30 days
      after a run ends, and at once for a run whose notebook or project is
      deleted. A hub read outage longer than a day so loses the sessions that
      start and end inside it; that is accepted.

  Only the server reads and records them.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Usage,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notebook_machines"
    schema("keyfleet_app")
    repo(Regents.Repo)

    custom_indexes do
      # The machines still running in a month or after it, counted month by
      # month (`:during`).
      index(["fleet_id", "(coalesce(ended_at, seen_at))"],
        name: "notebook_machines_counted_index"
      )
    end
  end

  actions do
    # Records each machine as the hub lists it now, in place of how it was
    # listed before.
    create :record do
      accept [:fleet_id, :id, :kind, :started_at, :ended_at, :seen_at]
      upsert? true
      upsert_fields [:ended_at, :seen_at]
    end

    # The fleet's machines that ran during the time from `from` until before
    # `to`, for counting a month's notebook hours
    # (`Regents.Keyfleet.Usage.Month.notebooks_counted/1`). Read through
    # `notebook_machines_counted_index`.
    read :during do
      argument :fleet_id, :string, allow_nil?: false
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :to, :utc_datetime_usec, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and started_at < ^arg(:to) and
                 fragment("coalesce(?, ?)", ended_at, seen_at) > ^arg(:from) and
                 fragment("coalesce(?, ?)", ended_at, seen_at) > started_at
             )
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false
    attribute :id, :string, primary_key?: true, allow_nil?: false
    attribute :kind, :atom, allow_nil?: false, constraints: [one_of: [:session, :run]]
    attribute :started_at, :utc_datetime_usec, allow_nil?: false

    # Nil while the hub has not said the machine ended.
    attribute :ended_at, :utc_datetime_usec

    attribute :seen_at, :utc_datetime_usec, allow_nil?: false
  end
end
