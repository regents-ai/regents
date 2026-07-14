defmodule AshPlatform.Billing.SpendReservation do
  use Ash.Resource,
    domain: AshPlatform.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "billing_spend_reservations"
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:billing_account_id, :status])
    end

    check_constraints do
      check_constraint(:amount_cents, "billing_spend_reservations_amount_positive",
        check: "amount_cents > 0",
        message: "must be positive"
      )

      check_constraint(:consumed_cents, "billing_spend_reservations_consumed_valid",
        check: "consumed_cents >= 0 AND consumed_cents <= amount_cents",
        message: "must be between zero and the reserved amount"
      )
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :reserve do
      public? false
      accept []
      argument :billing_account_id, :uuid, allow_nil?: false
      argument :operation_key, :string, allow_nil?: false
      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      change set_attribute(:billing_account_id, arg(:billing_account_id))
      change set_attribute(:operation_key, arg(:operation_key))
      change set_attribute(:amount_cents, arg(:amount_cents))
    end

    read :by_operation_key do
      public? false
      get? true
      argument :operation_key, :string, allow_nil?: false
      filter expr(operation_key == ^arg(:operation_key))
    end

    read :by_id do
      public? false
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    update :consume do
      public? false
      accept []
      argument :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
      validate AshPlatform.Billing.Validations.ReservationCanConsume
      change atomic_update(:consumed_cents, expr(consumed_cents + ^arg(:amount_cents)))

      change atomic_update(
               :status,
               expr(
                 if consumed_cents + ^arg(:amount_cents) == amount_cents do
                   :consumed
                 else
                   :active
                 end
               )
             )
    end

    update :close do
      public? false
      accept []

      argument :status, :atom,
        allow_nil?: false,
        constraints: [one_of: [:released, :expired]]

      validate AshPlatform.Billing.Validations.ActiveReservation
      change atomic_update(:status, arg(:status))
    end
  end

  policies do
    policy always() do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :globally_unique_operation_key, [:operation_key]
  end

  attributes do
    uuid_primary_key :id

    attribute :operation_key, :string,
      allow_nil?: false,
      constraints: [min_length: 1, max_length: 255]

    attribute :amount_cents, :integer, allow_nil?: false, constraints: [min: 1]
    attribute :consumed_cents, :integer, allow_nil?: false, default: 0

    attribute :status, :atom,
      allow_nil?: false,
      default: :active,
      constraints: [one_of: [:active, :consumed, :released, :expired]]

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :billing_account, AshPlatform.Billing.BillingAccount, allow_nil?: false
  end
end
