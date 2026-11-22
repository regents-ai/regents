defmodule Regents.Keyfleet.Graph.Relation do
  @moduledoc """
  One live link between two workspace objects, as the fleet's graph log last
  left it. A removed link has no row.

  Only the projector writes here, and only the fleet's members read it
  (`Regents.Keyfleet.Graph.Checks.KeyReader`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Graph,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @text [trim?: false]

  postgres do
    table "graph_relations"
    schema("keyfleet_app")
    repo(Regents.Repo)

    references do
      reference(:cursor, on_delete: :delete)
    end

    custom_indexes do
      index([:fleet_id, :source])
      # The links to an object.
      index([:fleet_id, :target, :type, :created_seq])
    end
  end

  actions do
    # The links from or to one object made after `after_seq`, oldest first.
    read :touching do
      argument :fleet_id, :string, allow_nil?: false
      argument :object_id, :string, allow_nil?: false, constraints: @text
      argument :after_seq, :integer, allow_nil?: false, constraints: [min: 0]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 201]

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 fragment("? > ?", created_seq, ^arg(:after_seq)) and
                 (source == ^arg(:object_id) or target == ^arg(:object_id))
             )

      prepare fn query, _context ->
        query
        |> Ash.Query.unset([:sort, :limit, :offset])
        |> Ash.Query.sort(created_seq: :asc)
        |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
      end
    end

    # The links from or to one object a page at a time, oldest first.
    read :linked do
      argument :fleet_id, :string, allow_nil?: false
      argument :object_id, :string, allow_nil?: false, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 (source == ^arg(:object_id) or target == ^arg(:object_id))
             )

      prepare build(sort: [created_seq: :asc])
      pagination keyset?: true, required?: true, default_limit: 50, max_page_size: 50
    end

    # The `produces` links to any of `targets`: the tasks that produced them.
    read :producing do
      argument :fleet_id, :string, allow_nil?: false

      argument :targets, {:array, :string},
        allow_nil?: false,
        constraints: [items: @text, max_length: 20]

      filter expr(fleet_id == ^arg(:fleet_id) and type == "produces" and target in ^arg(:targets))
      prepare build(sort: [created_seq: :asc], limit: 100)
    end

    # The links whose both ends are among `ids`, oldest first: the edges of
    # the workspace's graph between the items it draws. Callers bound it
    # with a limit.
    read :among do
      argument :fleet_id, :string, allow_nil?: false

      argument :ids, {:array, :string},
        allow_nil?: false,
        constraints: [items: @text, max_length: 200]

      filter expr(fleet_id == ^arg(:fleet_id) and source in ^arg(:ids) and target in ^arg(:ids))
      prepare build(sort: [created_seq: :asc])
    end

    read :with_ids do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :ids, {:array, :string}, allow_nil?: false, constraints: [items: @text]
      filter expr(fleet_id == ^arg(:fleet_id) and id in ^arg(:ids))
    end

    # Every link from or to an object of one project, for its deletion. Run
    # before the project's objects go.
    read :of_project do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 fragment(
                   "EXISTS (SELECT 1 FROM keyfleet_app.graph_objects AS o WHERE o.fleet_id = ? AND o.project = ? AND o.id IN (?, ?))",
                   ^arg(:fleet_id),
                   ^arg(:project),
                   source,
                   target
                 )
             )
    end

    create :project do
      public? false
      accept [:fleet_id, :id, :type, :source, :target, :data, :created_seq]
      upsert? true
      upsert_fields [:type, :source, :target, :data, :created_seq]
    end

    destroy :remove do
      public? false
    end
  end

  policies do
    policy action([:touching, :linked, :producing, :among]) do
      authorize_if Regents.Keyfleet.Graph.Checks.KeyReader
    end

    policy action([:with_ids, :project, :remove, :of_project]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true

    attribute :id, :string,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      constraints: @text

    attribute :type, :string, allow_nil?: false, public?: true, constraints: @text
    attribute :source, :string, allow_nil?: false, public?: true, constraints: @text
    attribute :target, :string, allow_nil?: false, public?: true, constraints: @text
    attribute :data, :map, allow_nil?: false, public?: true

    # The place in the log where the link was made.
    attribute :created_seq, Regents.Keyfleet.Graph.Seq, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :cursor, Regents.Keyfleet.Graph.Cursor do
      source_attribute :fleet_id
      destination_attribute :fleet_id
      define_attribute? false
    end
  end
end
