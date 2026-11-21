defmodule Regents.Keyfleet.Atlas.Bucket do
  @moduledoc """
  The fleet's work in one bucket of time (`Regents.Keyfleet.Atlas.Span`) for one
  project and one kind of thing: how many changes it took (`changes`), how
  many things changed (`things`) and the Keys that changed them (`keys`).

  Every change is counted into the bucket of every span that holds it, an
  hour, a day, a week, a month and a year, by `Regents.Keyfleet.Atlas.Count`, so a
  read of any span is a read of its own rows and never a sum: a thing changed
  in two hours of one day is one thing that day, and a Key at work all week is
  one Key that week. `Regents.Keyfleet.Atlas.Thing`'s `swarm` reads them
  (`Regents.Keyfleet.Atlas.Swarm`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Atlas,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Keyfleet.Atlas.Span

  # The primary key finds a stretch of one span; a project's rows are found
  # for its deletion.
  postgres do
    table "atlas_buckets"
    schema("keyfleet_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:fleet_id, :project])
    end
  end

  actions do
    # Adds counted changes to the buckets they fall in: a new bucket is made
    # with them, and one already there takes their changes, the things new to
    # it and their Keys.
    create :count do
      accept [:fleet_id, :span, :start, :project, :kind, :changes, :things, :keys]
      upsert? true
      upsert_fields [:changes, :things, :keys]

      change atomic_update(:changes, expr(changes + upsert_conflict(:changes)))
      change atomic_update(:things, expr(things + upsert_conflict(:things)))

      # Ash can't cast a list built in SQL; the column's own type holds it.
      change atomic_update(
               :keys,
               expr(
                 fragment(
                   "ARRAY(SELECT DISTINCT k FROM unnest(? || ?) AS k ORDER BY k)",
                   keys,
                   upsert_conflict(:keys)
                 )
               ),
               cast_atomic?: false
             )
    end

    read :of_project do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))
    end

    read :of_graph do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and kind != "notebook")
    end

    destroy :forget
  end

  # Only the system writes and reads these rows; readers read them through
  # `Regents.Keyfleet.Atlas.Thing`'s `swarm`.
  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :span, Span, primary_key?: true, allow_nil?: false, public?: true
    attribute :start, :utc_datetime, primary_key?: true, allow_nil?: false, public?: true
    attribute :project, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :kind, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :changes, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :things, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :keys, {:array, :integer}, allow_nil?: false, public?: true, default: []
  end
end
