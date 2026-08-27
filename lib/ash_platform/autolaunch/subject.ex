defmodule AshPlatform.Autolaunch.Subject do
  alias AshPlatform.Autolaunch.SubjectIdentity

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id, public?: false

    attribute :subject_id, :string do
      allow_nil? false
      public? true
      constraints SubjectIdentity.constraints()
    end

    attribute :subject_kind, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :chain_id, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :token_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :splitter_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :ingress_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :treasury_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    # The canonical zero-referral receiver this launch graduated with. Only
    # 490.8.2/.3 projection may fill it, so it stays null until then and every
    # payment action refuses while it is absent.
    attribute :canonical_receiver_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :factory_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :revenue_router_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :creator_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :staker_pool_bps, :integer do
      public? true
      constraints min: 0, max: 10_000
    end

    attribute :protocol_skim_bps_snapshot, :integer do
      public? true
      constraints min: 0, max: 10_000
    end

    attribute :current_protocol_skim_bps, :integer do
      public? true
      constraints min: 0, max: 10_000
    end

    attribute :protocol_fee_usdc_total_raw, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :regent_emission_total_raw, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :pending_buyback_usdc_raw, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    timestamps()
  end

  relationships do
    has_many :actions, AshPlatform.Autolaunch.SubjectAction
    has_many :payment_links, AshPlatform.Autolaunch.PaymentLink

    belongs_to :treasury_security_report,
               AshPlatform.Autolaunch.TreasurySecurityReport do
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
    end

    read :list_public do
      prepare build(sort: [inserted_at: :desc, id: :asc], load: [:treasury_security_report])
    end

    read :public_by_id do
      get? true

      argument :subject_id, :string,
        allow_nil?: false,
        constraints: SubjectIdentity.constraints()

      filter expr(subject_id == ^arg(:subject_id))
      prepare build(load: [:treasury_security_report])
    end

    create :import_public do
      accept [
        :subject_id,
        :subject_kind,
        :chain_id,
        :token_address,
        :splitter_address,
        :ingress_address,
        :treasury_address,
        :canonical_receiver_address,
        :factory_address,
        :creator_address,
        :staker_pool_bps,
        :protocol_skim_bps_snapshot,
        :current_protocol_skim_bps,
        :protocol_fee_usdc_total_raw,
        :regent_emission_total_raw,
        :pending_buyback_usdc_raw,
        :treasury_security_report_id
      ]
    end

    update :set_buyback_router do
      require_atomic? false
      accept [:revenue_router_address]
    end

    update :set_canonical_receiver do
      require_atomic? false
      accept [:canonical_receiver_address]
    end
  end

  policies do
    policy action([:read, :list_public, :public_by_id]) do
      authorize_if always()
    end

    policy action(:import_public) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action(:set_buyback_router) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action(:set_canonical_receiver) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_subject_id, [:subject_id]
  end

  postgres do
    table "subjects"
    schema("autolaunch")
    repo(AshPlatform.Repo)
  end
end
