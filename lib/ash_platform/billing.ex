defmodule AshPlatform.Billing do
  use Ash.Domain

  authorization do
    authorize :always
  end

  resources do
    resource AshPlatform.Billing.BillingAccount do
      define :record_provider_funding,
        action: :record_provider_funding,
        args: [:human_account_id, :provider_reference, :amount_cents]

      define :credit_summary, action: :credit_summary, args: [:human_account_id]

      define :reserve_spend,
        action: :reserve_spend,
        args: [:human_account_id, :operation_key, :amount_cents]

      define :consume_reserved_spend,
        action: :consume_reserved_spend,
        args: [:human_account_id, :reservation_id, :settlement_key, :amount_cents]

      define :release_reservation,
        action: :release_reservation,
        args: [:human_account_id, :reservation_id]

      define :expire_reservation,
        action: :expire_reservation,
        args: [:human_account_id, :reservation_id]
    end

    resource AshPlatform.Billing.LedgerEntry
    resource AshPlatform.Billing.SpendReservation
  end
end
