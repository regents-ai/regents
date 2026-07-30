defmodule AshPlatform.Techtree.Edge do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Techtree,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      default :prerequisite
      constraints one_of: [:prerequisite, :related]
    end

    timestamps()
  end

  relationships do
    belongs_to :from_node, AshPlatform.Techtree.Node do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :to_node, AshPlatform.Techtree.Node do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :list_for_tree do
      argument :tree_id, :uuid, allow_nil?: false
      filter expr(from_node.tree_id == ^arg(:tree_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    create :create do
      accept [:from_node_id, :to_node_id, :kind]
      change AshPlatform.Techtree.Edge.Changes.ValidateTopology
    end
  end

  policies do
    policy action(:list_for_tree) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_pair, [:from_node_id, :to_node_id]
  end

  postgres do
    table "edges"
    schema("techtree")
    repo(AshPlatform.Repo)
  end
end
