defmodule AshPlatform.Techtree.Node do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Techtree,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

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

    attribute :manifest_cid, :string do
      public? true
      constraints min_length: 1, max_length: 255
    end

    attribute :manifest_hash, :string do
      public? true
      constraints match: ~r/\A[0-9a-f]{64}\z/
    end

    attribute :manifest_uri, :string do
      public? true
      constraints max_length: 2_048
    end

    attribute :lineage, :map do
      public? true
    end

    attribute :projection_status, :atom do
      allow_nil? false
      public? true
      default :not_started
      constraints one_of: [:not_started, :pending, :submitted, :confirmed, :failed]
    end

    attribute :kind, :atom do
      public? true

      constraints one_of: [
                    :environment_family,
                    :benchmark_slice,
                    :uplift_report,
                    :reproduction,
                    :audit
                  ]
    end

    attribute :manifest_digest, :string do
      constraints match: ~r/\A[0-9a-f]{64}\z/
    end

    attribute :idempotency_key, :string do
      constraints min_length: 1, max_length: 255
    end

    attribute :contributor_id, :string do
      public? true
      constraints min_length: 1, max_length: 255
    end

    attribute :publisher_agent_id, :string do
      constraints min_length: 1, max_length: 255
    end

    attribute :publisher_registry_address, :string do
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :publisher_token_id, :string do
      constraints min_length: 1, max_length: 255
    end

    attribute :publisher_wallet, :string do
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :publisher_chain_id, :integer do
      constraints min: 8453, max: 8453
    end

    attribute :publisher_regent_id, :uuid
    attribute :siwa_envelope, :map

    attribute :pos_x, :float do
      public? true
    end

    attribute :pos_y, :float do
      public? true
    end

    attribute :display_kind, :string do
      allow_nil? false
      public? true
      default "standard"
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :published_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      default &DateTime.utc_now/0
    end

    attribute :workflow_state, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:draft, :publishing, :published, :failed]
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
    read :read do
      primary? true
      filter expr(workflow_state == :published and not is_nil(published_at))
    end

    read :list_public do
      filter expr(workflow_state == :published and not is_nil(published_at))
      prepare build(sort: [published_at: :desc, id: :asc])
    end

    read :list_public_for_tree do
      argument :tree_id, :uuid, allow_nil?: false

      filter expr(
               tree_id == ^arg(:tree_id) and workflow_state == :published and
                 not is_nil(published_at)
             )

      prepare build(sort: [published_at: :desc, id: :asc])
    end

    read :public_by_id do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and workflow_state == :published and not is_nil(published_at))
    end

    create :import_public do
      accept [
        :tree_id,
        :title,
        :summary,
        :payload_hash,
        :manifest_cid,
        :manifest_hash,
        :manifest_uri,
        :lineage
      ]

      change set_attribute(:workflow_state, :published)
    end

    create :create_publication do
      public? false

      accept [
        :tree_id,
        :kind,
        :title,
        :summary,
        :payload_hash,
        :manifest_digest,
        :manifest_cid,
        :manifest_hash,
        :manifest_uri,
        :lineage,
        :idempotency_key,
        :siwa_envelope
      ]

      change set_attribute(:workflow_state, :draft)
      change AshPlatform.Techtree.Node.Changes.AssignPublicationIdentity
      validate present(:idempotency_key)
    end

    update :mark_publication_publishing do
      public? false
      require_atomic? false
      accept []
      change set_attribute(:workflow_state, :publishing)
    end

    update :mark_publication_published do
      public? false
      require_atomic? false
      accept [:published_at]
      change set_attribute(:workflow_state, :published)
    end

    read :publication_by_key do
      get? true
      argument :registry_address, :string, allow_nil?: false
      argument :token_id, :string, allow_nil?: false
      argument :idempotency_key, :string, allow_nil?: false

      filter expr(
               publisher_registry_address == ^arg(:registry_address) and
                 publisher_token_id == ^arg(:token_id) and
                 idempotency_key == ^arg(:idempotency_key)
             )
    end

    update :update_layout do
      accept [:pos_x, :pos_y, :display_kind]
      require_atomic? false
    end
  end

  policies do
    policy action([:read, :list_public, :list_public_for_tree, :public_by_id]) do
      authorize_if always()
    end

    policy action([:import_public, :update_layout]) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action([
             :create_publication,
             :mark_publication_publishing,
             :mark_publication_published,
             :publication_by_key
           ]) do
      authorize_if AshPlatform.Techtree.Checks.AgentIdentity
    end

    policy action([:mark_publication_publishing, :mark_publication_published]) do
      authorize_if expr(
                     publisher_registry_address == ^actor(:registry_address) and
                       publisher_token_id == ^actor(:token_id)
                   )
    end
  end

  identities do
    identity :unique_publisher_idempotency,
             [:publisher_registry_address, :publisher_token_id, :idempotency_key]
  end

  postgres do
    table "nodes"
    schema("techtree")
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:tree_id, "published_at DESC", "id ASC"],
        name: "nodes_public_tree_page_index",
        concurrently: true
      )
    end
  end
end
