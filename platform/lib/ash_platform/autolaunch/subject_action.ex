defmodule AshPlatform.Autolaunch.SubjectAction do
  alias AshPlatform.Autolaunch.SubjectIdentity

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :action, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :owner_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :chain_id, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :tx_hash, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :amount, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :status, :string do
      allow_nil? false
      public? true
      default "pending"
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :block_number, :integer do
      public? true
      constraints min: 0
    end

    timestamps()
  end

  relationships do
    belongs_to :subject, AshPlatform.Autolaunch.Subject do
      allow_nil? false
    end
  end

  actions do
    read :recent_for_subject do
      argument :subject_identity, :string,
        allow_nil?: false,
        constraints: SubjectIdentity.constraints()

      filter expr(subject.subject_id == ^arg(:subject_identity))
      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 25)
    end

    read :settlements_for_subject do
      argument :subject_identity, :string,
        allow_nil?: false,
        constraints: SubjectIdentity.constraints()

      filter expr(subject.subject_id == ^arg(:subject_identity) and action == "settle_buyback")

      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 25)
    end

    create :import_public do
      argument :subject_identity, :string do
        allow_nil? false
        constraints SubjectIdentity.constraints()
      end

      accept [
        :action,
        :owner_address,
        :chain_id,
        :tx_hash,
        :amount,
        :status,
        :block_number
      ]

      change AshPlatform.Autolaunch.SubjectAction.Changes.ResolveSubject
    end
  end

  policies do
    policy action([:recent_for_subject, :settlements_for_subject]) do
      authorize_if always()
    end

    policy action(:import_public) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  postgres do
    table "subject_actions"
    schema("autolaunch_app")
    migrate?(false)
    repo(AshPlatform.Repo)
  end
end
