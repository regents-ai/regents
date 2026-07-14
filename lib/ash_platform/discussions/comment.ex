defmodule AshPlatform.Discussions.Comment do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Discussions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :target_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:techtree_node, :autolaunch_auction, :autolaunch_token]
    end

    attribute :target_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :body, :string do
      allow_nil? false
      public? true
      constraints max_length: 16_000
    end

    attribute :client_request_id, :uuid do
      allow_nil? false
    end

    attribute :deleted_at, :utc_datetime_usec
    attribute :deleted_by_human_account_id, :integer
    attribute :deletion_authority, :atom
    timestamps()
  end

  relationships do
    belongs_to :author, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
      read_action :public_comment_author
    end
  end

  actions do
    create :post do
      accept []

      argument :target_type, :atom do
        allow_nil? false
        constraints one_of: [:techtree_node, :autolaunch_auction, :autolaunch_token]
      end

      argument :target_id, :uuid, allow_nil?: false
      argument :body, :string, allow_nil?: false
      argument :client_request_id, :uuid, allow_nil?: false

      change AshPlatform.Discussions.Comment.Changes.AssignHumanAuthor
      change AshPlatform.Discussions.Comment.Changes.ValidateAndNormalize
      change AshPlatform.Discussions.Comment.Changes.Broadcast

      upsert? true
      upsert_identity :unique_author_request
      upsert_fields []

      upsert_condition expr(
                         target_type == upsert_conflict(:target_type) and
                           target_id == upsert_conflict(:target_id) and
                           body == upsert_conflict(:body)
                       )
    end

    read :list_for_target do
      argument :target_type, :atom do
        allow_nil? false
        constraints one_of: [:techtree_node, :autolaunch_auction, :autolaunch_token]
      end

      argument :target_id, :uuid, allow_nil?: false

      filter expr(
               target_type == ^arg(:target_type) and target_id == ^arg(:target_id) and
                 is_nil(deleted_at)
             )

      prepare build(load: [:author], sort: [inserted_at: :desc, id: :desc])
    end

    read :audit_by_id do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    update :delete do
      accept []
      require_atomic? false
      filter expr(is_nil(deleted_at))
      change AshPlatform.Discussions.Comment.Changes.MarkDeletion
      change AshPlatform.Discussions.Comment.Changes.Broadcast
    end
  end

  policies do
    policy action(:list_for_target) do
      authorize_if always()
    end

    policy action([:post, :delete]) do
      authorize_if AshPlatform.Discussions.Comment.Checks.HumanActor
    end

    policy action(:delete) do
      forbid_if expr(not is_nil(deleted_at))
      authorize_if expr(author_id == ^actor(:human_account_id))
      authorize_if AshPlatform.Discussions.Comment.Checks.AdminWallet
    end

    policy action(:audit_by_id) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_author_request, [:author_id, :client_request_id]
  end

  postgres do
    table "comments"
    schema("discussions")
    repo(AshPlatform.Repo)
  end
end
