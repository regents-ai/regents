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
    :treasury_path,
    :required_regent_raised
  ]

  @eoa_acknowledgement "This auction will be owned by my EOA private key, and significant harm and token value will happen if it is lost or compromised. I was warned to create a Gnosis Safe or 0xSplits smart account as the owner, and I realize auction bidders and token owners will see that it is EOA-owned and more risky. I accept these problems, and wish to continue with EOA ownership of the token."

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

    attribute :treasury_path, :atom do
      allow_nil? false
      public? true
      default :safe
      constraints one_of: [:safe, :eoa, :contract]
    end

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
      argument :eoa_acknowledgement, :string, constraints: [trim?: false]
      accept @clean_v1_fields
      validate AshPlatform.Autolaunch.LaunchDraft.Validations.CleanV1Fields

      validate argument_equals(:eoa_acknowledgement, @eoa_acknowledgement),
        where: [attribute_equals(:treasury_path, :eoa)]

      change AshPlatform.Autolaunch.LaunchDraft.Changes.AssignOwnerAndRegent
    end

    read :mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [updated_at: :desc, id: :asc])
    end

    update :revise_by_owner do
      argument :eoa_acknowledgement, :string, constraints: [trim?: false]
      accept @clean_v1_fields
      require_atomic? false
      validate AshPlatform.Autolaunch.LaunchDraft.Validations.CleanV1Fields

      validate argument_equals(:eoa_acknowledgement, @eoa_acknowledgement),
        where: [attribute_equals(:treasury_path, :eoa)]
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
