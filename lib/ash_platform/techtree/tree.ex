defmodule AshPlatform.Techtree.Tree do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Techtree,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints max_length: 63, match: ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :description, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 500, trim?: true
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  actions do
    read :list_public do
      prepare build(sort: [position: :asc])
    end

    read :public_by_slug do
      get? true
      argument :slug, :string, allow_nil?: false
      filter expr(slug == ^arg(:slug))
    end

    create :upsert_seed_root do
      accept [:slug, :name, :description, :position]
      upsert? true
      upsert_identity :unique_slug
      upsert_fields [:name, :description, :position]
    end
  end

  policies do
    policy action([:list_public, :public_by_slug]) do
      authorize_if always()
    end

    policy action(:upsert_seed_root) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_slug, [:slug]
    identity :unique_position, [:position]
  end

  postgres do
    table "trees"
    schema("techtree")
    repo(AshPlatform.Repo)
  end
end
