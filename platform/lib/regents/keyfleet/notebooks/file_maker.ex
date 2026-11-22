defmodule Regents.Keyfleet.Notebooks.FileMaker do
  @moduledoc """
  Who made a file or folder in a notebook's workspace, by its path there: the
  member who added it (`Regents.Keyfleet.Notebooks.Makers`). A path with no maker
  kept here was there before Keyfleet kept them, or was written by a run, and
  is the notebook's maker's.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Notebooks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notebook_file_makers"
    schema("keyfleet_app")
    repo(Regents.Repo)
  end

  actions do
    create :record do
      accept [:fleet_id, :notebook_id, :path, :maker]
      upsert? true
      upsert_identity :unique_path
      upsert_fields [:maker]
    end

    # The path and everything under it.
    read :at_or_under do
      argument :fleet_id, :string, allow_nil?: false
      argument :notebook_id, :string, allow_nil?: false
      argument :path, :string, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and notebook_id == ^arg(:notebook_id) and
                 (path == ^arg(:path) or fragment("starts_with(?, ? || '/')", path, ^arg(:path)))
             )
    end

    destroy :forget
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  identities do
    identity :unique_path, [:fleet_id, :notebook_id, :path]
  end

  attributes do
    uuid_primary_key :id
    attribute :fleet_id, :string, allow_nil?: false
    attribute :notebook_id, :string, allow_nil?: false
    attribute :path, :string, allow_nil?: false
    attribute :maker, :string, allow_nil?: false
    create_timestamp :inserted_at
  end
end
