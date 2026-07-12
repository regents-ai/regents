defmodule AshPlatform.Techtree.Node do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Techtree,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200, trim?: true
    end

    attribute :summary, :string do
      public? true
      constraints max_length: 2_000, trim?: true
    end

    attribute :payload_hash, :string do
      public? true
      constraints max_length: 128
    end

    attribute :published_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      default &DateTime.utc_now/0
    end

    timestamps()
  end

  relationships do
    belongs_to :tree, AshPlatform.Techtree.Tree do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :list_public do
      prepare build(sort: [published_at: :desc, id: :asc])
    end

    read :list_public_for_tree do
      argument :tree_id, :uuid, allow_nil?: false
      filter expr(tree_id == ^arg(:tree_id))
      prepare build(sort: [published_at: :desc, id: :asc])
    end

    read :public_by_id do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    create :import_public do
      accept [:tree_id, :title, :summary, :payload_hash]
    end
  end

  policies do
    policy action([:list_public, :list_public_for_tree, :public_by_id]) do
      authorize_if always()
    end

    policy action(:import_public) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  postgres do
    table "nodes"
    schema("techtree")
    repo(AshPlatform.Repo)
  end
end
