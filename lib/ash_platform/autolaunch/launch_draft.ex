defmodule AshPlatform.Autolaunch.LaunchDraft do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 160, trim?: true
    end

    attribute :token_name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :symbol, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 16, match: ~r/\A[A-Z0-9]+\z/
    end

    attribute :summary, :string do
      public? true
      constraints max_length: 2_000, trim?: true
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
    create :create_for_my_regent do
      accept [:title, :token_name, :symbol, :summary]
      change AshPlatform.Autolaunch.LaunchDraft.Changes.AssignOwnerAndRegent
    end

    read :mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [updated_at: :desc, id: :asc])
    end
  end

  policies do
    policy action([:create_for_my_regent, :mine]) do
      authorize_if AshPlatform.Formation.Checks.HumanActor
    end

    policy action(:mine) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  postgres do
    table "launch_drafts"
    schema("autolaunch")
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:human_account_id])
      index([:regent_id])
    end
  end
end
