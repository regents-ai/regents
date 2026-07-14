defmodule AshPlatform.Billing.BillingAccount do
  use Ash.Resource,
    domain: AshPlatform.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "billing_accounts"
    repo(AshPlatform.Repo)

    check_constraints do
      check_constraint(:funded_cents, "billing_accounts_funded_non_negative",
        check: "funded_cents >= 0",
        message: "must not be negative"
      )

      check_constraint(:reserved_cents, "billing_accounts_reserved_non_negative",
        check: "reserved_cents >= 0",
        message: "must not be negative"
      )

      check_constraint(:consumed_cents, "billing_accounts_consumed_non_negative",
        check: "consumed_cents >= 0",
        message: "must not be negative"
      )

      check_constraint(
        [:funded_cents, :reserved_cents, :consumed_cents],
        "billing_accounts_authority_balanced",
        check: "funded_cents >= reserved_cents + consumed_cents",
        message: "cannot authorize more credit than was funded"
      )
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :open do
      public? false
      accept []
      argument :human_account_id, :integer, allow_nil?: false
      change set_attribute(:human_account_id, arg(:human_account_id))
      upsert? true
      upsert_identity :one_per_human_account
      upsert_fields []
    end

    read :by_human_account do
      public? false
      get? true
      argument :human_account_id, :integer, allow_nil?: false
      filter expr(human_account_id == ^arg(:human_account_id))
    end

    read :by_id do
      public? false
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    update :add_funding do
      public? false
      accept []
      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      change atomic_update(:funded_cents, expr(funded_cents + ^arg(:amount_cents)))
    end

    update :increase_reserved do
      public? false
      accept []
      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      validate AshPlatform.Billing.Validations.HasAvailableCredit
      change atomic_update(:reserved_cents, expr(reserved_cents + ^arg(:amount_cents)))
    end

    update :settle_reserved do
      public? false
      accept []
      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      validate AshPlatform.Billing.Validations.HasReservedCredit
      change atomic_update(:reserved_cents, expr(reserved_cents - ^arg(:amount_cents)))
      change atomic_update(:consumed_cents, expr(consumed_cents + ^arg(:amount_cents)))
    end

    update :return_reserved do
      public? false
      accept []
      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      validate AshPlatform.Billing.Validations.HasReservedCredit
      change atomic_update(:reserved_cents, expr(reserved_cents - ^arg(:amount_cents)))
    end

    action :record_provider_funding, :struct do
      constraints instance_of: AshPlatform.Billing.LedgerEntry
      argument :human_account_id, :integer, allow_nil?: false

      argument :provider_reference, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 255]

      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      run AshPlatform.Billing.Actions.RecordProviderFunding
    end

    action :credit_summary, :map do
      argument :human_account_id, :integer, allow_nil?: false
      run AshPlatform.Billing.Actions.CreditSummary
    end

    action :reserve_spend, :struct do
      constraints instance_of: AshPlatform.Billing.SpendReservation
      argument :human_account_id, :integer, allow_nil?: false

      argument :operation_key, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 255]

      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      run AshPlatform.Billing.Actions.ReserveSpend
    end

    action :consume_reserved_spend, :struct do
      constraints instance_of: AshPlatform.Billing.SpendReservation
      argument :human_account_id, :integer, allow_nil?: false
      argument :reservation_id, :uuid, allow_nil?: false

      argument :settlement_key, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 255]

      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      run {AshPlatform.Billing.Actions.TransitionReservation, transition: :consume}
    end

    action :release_reservation, :struct do
      constraints instance_of: AshPlatform.Billing.SpendReservation
      argument :human_account_id, :integer, allow_nil?: false
      argument :reservation_id, :uuid, allow_nil?: false
      run {AshPlatform.Billing.Actions.TransitionReservation, transition: :release}
    end

    action :expire_reservation, :struct do
      constraints instance_of: AshPlatform.Billing.SpendReservation
      argument :human_account_id, :integer, allow_nil?: false
      argument :reservation_id, :uuid, allow_nil?: false
      run {AshPlatform.Billing.Actions.TransitionReservation, transition: :expire}
    end
  end

  policies do
    policy action([
             :open,
             :by_human_account,
             :by_id,
             :add_funding,
             :increase_reserved,
             :settle_reserved,
             :return_reserved
           ]) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action(:record_provider_funding) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action([
             :credit_summary,
             :reserve_spend,
             :consume_reserved_spend,
             :release_reservation,
             :expire_reservation
           ]) do
      authorize_if AshPlatform.Billing.Checks.ActorOwnsInputAccount
    end
  end

  identities do
    identity :one_per_human_account, [:human_account_id]
  end

  attributes do
    uuid_primary_key :id
    attribute :currency, :atom, allow_nil?: false, default: :usd, constraints: [one_of: [:usd]]
    attribute :funded_cents, :integer, allow_nil?: false, default: 0
    attribute :reserved_cents, :integer, allow_nil?: false, default: 0
    attribute :consumed_cents, :integer, allow_nil?: false, default: 0
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end
end
