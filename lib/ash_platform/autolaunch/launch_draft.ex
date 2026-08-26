defmodule AshPlatform.Autolaunch.LaunchDraft do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @clean_v1_fields [
    :name,
    :symbol,
    :description,
    :website,
    :image,
    :treasury,
    :required_regent_raised
  ]

  attributes do
    uuid_primary_key :id

    # Superseded launch-page title. It is never read or written by the current
    # route; it exists only so rows written before clean V1 stay intact.
    attribute :title, :string

    attribute :name, :string do
      source :token_name
      allow_nil? false
      public? true
    end

    attribute :symbol, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      source :summary
      public? true
    end

    attribute :website, :string, public?: true
    attribute :image, :string, public?: true
    attribute :treasury, :string, public?: true
    attribute :required_regent_raised, :string, public?: true

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
      accept @clean_v1_fields
      validate AshPlatform.Autolaunch.LaunchDraft.Validations.CleanV1Fields
      change AshPlatform.Autolaunch.LaunchDraft.Changes.AssignOwnerAndRegent
    end

    read :mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [updated_at: :desc, id: :asc])
    end

    update :revise_by_owner do
      accept @clean_v1_fields
      require_atomic? false
      validate AshPlatform.Autolaunch.LaunchDraft.Validations.CleanV1Fields
    end
  end

  policies do
    policy action([:create_for_my_regent, :mine, :revise_by_owner]) do
      authorize_if AshPlatform.Formation.Checks.HumanActor
    end

    policy action([:mine, :revise_by_owner]) do
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
