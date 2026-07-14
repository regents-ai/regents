defmodule AshPlatform.Billing.LedgerEntry do
  use Ash.Resource,
    domain: AshPlatform.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "billing_ledger_entries"
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:provider_reference], unique: true, where: "provider_reference IS NOT NULL")
      index([:billing_account_id, :created_at])
    end

    check_constraints do
      check_constraint(:amount_cents, "billing_ledger_entries_amount_positive",
        check: "amount_cents > 0",
        message: "must be positive"
      )
    end
  end

  actions do
    create :append do
      public? false
      accept []
      argument :billing_account_id, :uuid, allow_nil?: false

      argument :kind, :atom,
        allow_nil?: false,
        constraints: [one_of: [:provider_funding, :reservation_consumption]]

      argument :idempotency_key, :string, allow_nil?: false
      argument :provider_reference, :string
      argument :reservation_id, :uuid
      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      change set_attribute(:billing_account_id, arg(:billing_account_id))
      change set_attribute(:kind, arg(:kind))
      change set_attribute(:idempotency_key, arg(:idempotency_key))
      change set_attribute(:provider_reference, arg(:provider_reference))
      change set_attribute(:reservation_id, arg(:reservation_id))
      change set_attribute(:amount_cents, arg(:amount_cents))
    end

    read :by_idempotency_key do
      public? false
      get? true
      argument :idempotency_key, :string, allow_nil?: false
      filter expr(idempotency_key == ^arg(:idempotency_key))
    end
  end

  policies do
    policy always() do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :globally_unique_idempotency_key, [:idempotency_key]
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      constraints: [one_of: [:provider_funding, :reservation_consumption]]

    attribute :idempotency_key, :string,
      allow_nil?: false,
      constraints: [min_length: 1, max_length: 320]

    attribute :provider_reference, :string, constraints: [min_length: 1, max_length: 255]
    attribute :reservation_id, :uuid
    attribute :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
    create_timestamp :created_at
  end

  relationships do
    belongs_to :billing_account, AshPlatform.Billing.BillingAccount, allow_nil?: false
  end
end
