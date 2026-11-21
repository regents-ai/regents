defmodule Regents.Keyfleet.Notebooks.Setting do
  @moduledoc """
  What Keyfleet keeps about one notebook beyond what its hub keeps: the Key
  whose scratchpad it is (`key`, `Regents.Keyfleet.Notebooks.Scratchpads`), and
  whether its creator unlocked it (`unlocked`).

  A notebook with no row here is locked and is nobody's scratchpad. Locked,
  the fleet's members open, copy and run it, and only its creator changes it;
  unlocked, any member edits it too, and still only its creator deletes it or
  locks it again (`Regents.Keyfleet.Notebooks.Makers`). A scratchpad's creator is
  whoever acts as its Key (`Regents.Keyfleet.Graph.Checks.KeyActor`). The row goes
  when the notebook is deleted, so a Key whose scratchpad was deleted gets a
  new one.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Notebooks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notebook_settings"
    schema("keyfleet_app")
    repo(Regents.Repo)
  end

  actions do
    defaults [:read]

    read :of do
      get? true
      argument :fleet_id, :string, allow_nil?: false
      argument :notebook_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and notebook_id == ^arg(:notebook_id))
    end

    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id))
    end

    # The fleet's scratchpads, by Key.
    read :scratchpads do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and not is_nil(key))
      prepare build(sort: [key: :asc])
    end

    create :scratchpad do
      accept [:fleet_id, :notebook_id, :key]
      upsert? true
      upsert_identity :unique_notebook
      upsert_fields []
    end

    create :switch do
      accept [:fleet_id, :notebook_id, :unlocked]
      upsert? true
      upsert_identity :unique_notebook
      upsert_fields [:unlocked]
    end

    destroy :forget
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  identities do
    identity :unique_notebook, [:fleet_id, :notebook_id]
    identity :one_scratchpad_per_key, [:fleet_id, :key]
  end

  attributes do
    uuid_primary_key :id
    attribute :fleet_id, :string, allow_nil?: false
    attribute :notebook_id, :string, allow_nil?: false
    attribute :key, :integer, constraints: [min: 0]
    attribute :unlocked, :boolean, allow_nil?: false, default: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
