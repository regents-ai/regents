defmodule AshPlatform.Discussions.CommentReaction do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Discussions,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    create :set do
      accept []

      argument :comment_id, :uuid, allow_nil?: false

      argument :value, :atom do
        allow_nil? false
        constraints one_of: [:useful, :off_topic, :negative]
      end

      change AshPlatform.Discussions.CommentReaction.Changes.AssignHumanReactor
      change AshPlatform.Discussions.CommentReaction.Changes.ValidateComment
      change set_attribute(:comment_id, arg(:comment_id))
      change set_attribute(:value, arg(:value))
      change AshPlatform.Discussions.CommentReaction.Changes.Broadcast

      upsert? true
      upsert_identity :unique_reactor_comment
      upsert_fields [:value]
    end

    read :list_for_comments do
      argument :comment_ids, {:array, :uuid}, allow_nil?: false
      filter expr(comment_id in ^arg(:comment_ids))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :mine_for_comment do
      get? true
      argument :comment_id, :uuid, allow_nil?: false
      filter expr(comment_id == ^arg(:comment_id) and reactor_id == ^actor(:human_account_id))
    end

    destroy :remove do
      accept []
      require_atomic? false
      change AshPlatform.Discussions.CommentReaction.Changes.Broadcast
    end
  end

  policies do
    policy action(:list_for_comments) do
      authorize_if always()
    end

    policy action(:set) do
      authorize_if AshPlatform.Discussions.Comment.Checks.HumanActor
    end

    policy action(:mine_for_comment) do
      authorize_if AshPlatform.Discussions.Comment.Checks.HumanActor
    end

    policy action(:remove) do
      authorize_if AshPlatform.Discussions.Comment.Checks.HumanActor
    end

    policy action(:remove) do
      authorize_if expr(reactor_id == ^actor(:human_account_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :value, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:useful, :off_topic, :negative]
    end

    timestamps()
  end

  relationships do
    belongs_to :comment, AshPlatform.Discussions.Comment do
      allow_nil? false
    end

    belongs_to :reactor, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :unique_reactor_comment, [:reactor_id, :comment_id]
  end

  postgres do
    table "comment_reactions"
    schema("discussions")
    repo(AshPlatform.Repo)
  end
end
