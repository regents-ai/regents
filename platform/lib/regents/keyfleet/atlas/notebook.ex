defmodule Regents.Keyfleet.Atlas.Notebook do
  @moduledoc """
  One of the fleet's notebooks as its hub last listed it, kept by
  `Regents.Keyfleet.Atlas.ReadHub`: the project it is in and that project's space in
  the hub, its title and author, the Key it is counted as
  (`Regents.Keyfleet.Notebooks.keys/2`), and when it was made and last updated. The
  project's notebook updated last says where the next read of the hub starts
  (`last_updated`). A project deleted takes its notebooks with it
  (`Regents.Keyfleet.Projects.Changes.Forget`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Atlas,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "atlas_notebooks"
    schema("keyfleet_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:fleet_id, :project, :updated_at])
    end
  end

  actions do
    read :with_ids do
      argument :fleet_id, :string, allow_nil?: false
      argument :ids, {:array, :string}, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and id in ^arg(:ids))
    end

    # The project's notebook updated last.
    read :last_updated do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))
      prepare build(sort: [updated_at: :desc], limit: 1)
    end

    create :keep do
      accept [:fleet_id, :id, :project, :space, :title, :author, :key, :created_at, :updated_at]
      upsert? true
      upsert_fields [:title, :author, :key, :updated_at]
    end

    read :of_project do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))
    end

    destroy :forget
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true

    attribute :id, :string,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false]

    attribute :project, :string, allow_nil?: false, public?: true
    attribute :space, :string, allow_nil?: false, public?: true

    attribute :title, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false, allow_empty?: true]

    attribute :author, :string, allow_nil?: false, public?: true
    attribute :key, :integer, public?: true
    attribute :created_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end
end
