defmodule Regents.Keyfleet.Atlas.Thing do
  @moduledoc """
  One thing's work in one bucket of time (`Regents.Keyfleet.Atlas.Span`): an item of
  the workspace or a notebook (`thing`, its id), of its `kind` and `project`,
  with how many changes it took there (`changes`), the Keys that made them
  (`keys`, and how many: `actors`), and when it last changed and as which
  Key (`last_at`, `last_key`, nil for the workspace's own doing).

  As `Regents.Keyfleet.Atlas.Bucket`, every change is counted into the row of every
  span that holds it (`Regents.Keyfleet.Atlas.Count`), so a window of any span is one
  bucket's rows: `most_active` and `newest` each read one window, a page at a
  time, in the order an index keeps them.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Atlas,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Keyfleet.Atlas.{Named, Source, Span, Window}

  postgres do
    table "atlas_things"
    schema("keyfleet_app")
    repo(Regents.Repo)

    # Each window's things in each order the reads keep, for the whole fleet,
    # one kind (notebooks among them) and one project, so every page is a
    # range of one index read from its end.
    custom_indexes do
      index([:fleet_id, :span, :start, :changes, :actors, :thing],
        name: "atlas_things_active_index"
      )

      index([:fleet_id, :kind, :span, :start, :changes, :actors, :thing],
        name: "atlas_things_kind_active_index"
      )

      index([:fleet_id, :project, :span, :start, :changes, :actors, :thing],
        name: "atlas_things_project_active_index"
      )

      index([:fleet_id, :span, :start, :last_at, :thing], name: "atlas_things_newest_index")

      index([:fleet_id, :kind, :span, :start, :last_at, :thing],
        name: "atlas_things_kind_newest_index"
      )

      index([:fleet_id, :project, :span, :start, :last_at, :thing],
        name: "atlas_things_project_newest_index"
      )
    end
  end

  actions do
    # The things of one window with the most changes, then the most Keys,
    # first.
    read :most_active do
      argument :fleet_id, :string, allow_nil?: false
      argument :span, Span, allow_nil?: false
      argument :at, :utc_datetime_usec, allow_nil?: false
      argument :source, Source
      argument :project, :string
      argument :kind, :string
      prepare Window
      prepare build(sort: [changes: :desc, actors: :desc, thing: :desc])
      pagination keyset?: true, required?: true, default_limit: 20, max_page_size: 200
    end

    # The things of one window, the one changed last first.
    read :newest do
      argument :fleet_id, :string, allow_nil?: false
      argument :span, Span, allow_nil?: false
      argument :at, :utc_datetime_usec, allow_nil?: false
      argument :source, Source
      argument :project, :string
      argument :kind, :string
      prepare Window
      prepare build(sort: [last_at: :desc, thing: :desc])
      pagination keyset?: true, required?: true, default_limit: 20, max_page_size: 200
    end

    # Which of these things already have a row in any of these buckets.
    read :existing do
      argument :fleet_id, :string, allow_nil?: false
      argument :things, {:array, :string}, allow_nil?: false
      argument :starts, {:array, :utc_datetime}, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and thing in ^arg(:things) and
                 start in ^arg(:starts)
             )

      prepare build(select: [:fleet_id, :thing, :span, :start])
    end

    # Adds counted changes to the things' rows: a new row is made with them,
    # and one already there takes their changes and their Keys, and the last
    # change if it came later.
    create :count do
      accept [
        :fleet_id,
        :thing,
        :span,
        :start,
        :kind,
        :project,
        :changes,
        :keys,
        :actors,
        :last_at,
        :last_key
      ]

      upsert? true
      upsert_fields [:changes, :keys, :actors, :last_at, :last_key]

      change atomic_update(:changes, expr(changes + upsert_conflict(:changes)))

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

      change atomic_update(
               :actors,
               expr(
                 fragment(
                   "cardinality(ARRAY(SELECT DISTINCT k FROM unnest(? || ?) AS k))",
                   keys,
                   upsert_conflict(:keys)
                 )
               )
             )

      change atomic_update(
               :last_key,
               expr(
                 if upsert_conflict(:last_at) >= last_at,
                   do: upsert_conflict(:last_key),
                   else: last_key
               )
             )

      change atomic_update(
               :last_at,
               expr(fragment("greatest(?, ?)", last_at, upsert_conflict(:last_at)))
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

    # The swarm over a stretch of time, read from the buckets
    # (`Regents.Keyfleet.Atlas.Bucket`) rather than these rows. It runs from a
    # function, so a change to `Regents.Keyfleet.Atlas.Swarm` recompiles nothing here.
    action :swarm, {:array, :map} do
      description "The fleet's changes, things changed and Keys at work in each bucket of a stretch of time."
      argument :fleet_id, :string, allow_nil?: false
      argument :span, Span, allow_nil?: false
      argument :from, :utc_datetime, allow_nil?: false
      argument :to, :utc_datetime, allow_nil?: false
      argument :source, Source
      argument :project, :string

      argument :by, {:array, :atom},
        allow_nil?: false,
        default: [:project, :kind],
        constraints: [items: [one_of: [:project, :kind]]]

      validate Regents.Keyfleet.Atlas.Validations.Stretch
      run fn input, _context -> Regents.Keyfleet.Atlas.Swarm.run(input.arguments) end
    end
  end

  policies do
    # The fleet's work is read as its workspace is.
    policy action([:swarm, :most_active, :newest]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :workspace, scope: :fleet_id}
    end

    policy action([:existing, :count, :of_project, :of_graph, :forget]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true

    attribute :thing, :string,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false]

    attribute :span, Span, primary_key?: true, allow_nil?: false, public?: true
    attribute :start, :utc_datetime, primary_key?: true, allow_nil?: false, public?: true
    attribute :kind, :string, allow_nil?: false, public?: true
    attribute :project, :string, allow_nil?: false, public?: true
    attribute :changes, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
    attribute :keys, {:array, :integer}, allow_nil?: false, public?: true, default: []
    attribute :actors, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :last_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_key, :integer, public?: true
  end

  calculations do
    # What the thing is called now: an item's title as the workspace names it,
    # or a notebook's as the hub last listed it.
    calculate :title, :string, {Named, field: :title}, public?: true

    # The notebook's space in the fleet's hub, which its link opens in; nil
    # for an item of the workspace.
    calculate :space, :string, {Named, field: :space}, public?: true
  end
end
