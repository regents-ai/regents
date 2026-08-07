defmodule AshPlatform.Techtree.EvidenceStateUpdate do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Techtree,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @statuses [:reproduced, :disputed, :superseded, :expired, :invalidated]

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: @statuses
    end

    attribute :reason, :string do
      public? true
      constraints max_length: 2_000
    end

    attribute :evidence_reference_ids, {:array, :uuid} do
      allow_nil? false
      public? true
      default []
      constraints max_length: 100
    end

    attribute :submitter_agent_id, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255
    end

    attribute :submitter_registry_address, :string do
      allow_nil? false
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :submitter_token_id, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255
    end

    attribute :submitter_wallet, :string do
      allow_nil? false
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :submitter_chain_id, :integer do
      allow_nil? false
      constraints min: 8_453, max: 8_453
    end

    attribute :submitter_regent_id, :uuid do
      allow_nil? false
    end

    attribute :siwa_envelope, :map do
      allow_nil? false
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :node, AshPlatform.Techtree.Node do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
    end

    read :latest_for_node do
      argument :node_id, :uuid, allow_nil?: false

      filter expr(node_id == ^arg(:node_id))
      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 1)
    end

    read :all_for_node do
      argument :node_id, :uuid, allow_nil?: false

      filter expr(node_id == ^arg(:node_id))
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    create :append do
      public? false
      accept []

      argument :node_id, :uuid, allow_nil?: false

      argument :status, :atom,
        allow_nil?: false,
        constraints: [one_of: @statuses]

      argument :reason, :string, constraints: [max_length: 2_000]

      argument :evidence_reference_ids, {:array, :uuid},
        default: [],
        constraints: [max_length: 100]

      argument :siwa_envelope, :map, allow_nil?: false

      change set_attribute(:node_id, arg(:node_id))
      change set_attribute(:status, arg(:status))
      change set_attribute(:reason, arg(:reason))
      change set_attribute(:evidence_reference_ids, arg(:evidence_reference_ids))
      change AshPlatform.Techtree.EvidenceStateUpdate.Changes.PrepareAppend
    end
  end

  policies do
    policy action([:read, :latest_for_node, :all_for_node]) do
      authorize_if always()
    end

    policy action(:append) do
      authorize_if AshPlatform.Techtree.Checks.PublisherOwnsNode
    end
  end

  postgres do
    table "evidence_state_updates"
    schema("techtree")
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:node_id, "inserted_at DESC", "id DESC"],
        name: "evidence_state_updates_node_latest_index"
      )
    end
  end

  def latest_for_node(node_id) do
    __MODULE__
    |> Ash.Query.for_read(:latest_for_node, %{node_id: node_id}, actor: nil)
    |> Ash.read_one()
  end

  def all_for_node(node_id) do
    __MODULE__
    |> Ash.Query.for_read(:all_for_node, %{node_id: node_id}, actor: nil)
    |> Ash.read()
  end
end
