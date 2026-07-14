defmodule AshPlatform.Formation.CloudRuntime do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Formation,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :provider_sprite_id, :string do
      allow_nil? false
      sensitive? true
      constraints min_length: 1, max_length: 160
    end

    attribute :sprite_name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, match: ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    end

    attribute :url, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 2_048
    end

    attribute :provider_status, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 80
    end

    attribute :observed_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    belongs_to :regent, AshPlatform.Formation.Regent do
      allow_nil? false
    end
  end

  actions do
    create :provision_for_my_regent do
      accept []
      change AshPlatform.Formation.CloudRuntime.Changes.Provision
      upsert? true
      upsert_identity :unique_regent
      upsert_fields [:provider_sprite_id, :sprite_name, :url, :provider_status, :observed_at]
      upsert_condition expr(human_account_id == ^actor(:human_account_id))
    end

    read :mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :public_profile_source do
      public? false
      get? true
      argument :regent_id, :uuid, allow_nil?: false
      filter expr(regent_id == ^arg(:regent_id))
    end

    update :refresh_status do
      accept []
      require_atomic? false
      change AshPlatform.Formation.CloudRuntime.Changes.RefreshStatus
    end
  end

  policies do
    policy action([:provision_for_my_regent, :mine, :refresh_status]) do
      authorize_if AshPlatform.Formation.Checks.HumanActor
    end

    policy action(:public_profile_source) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action([:mine, :refresh_status]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :unique_regent, [:regent_id]
    identity :unique_sprite_name, [:sprite_name]
    identity :unique_provider_sprite, [:provider_sprite_id]
  end

  postgres do
    table "cloud_runtimes"
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:human_account_id])
    end
  end
end
