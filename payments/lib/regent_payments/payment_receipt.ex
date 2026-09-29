defmodule RegentPayments.PaymentReceipt do
  @moduledoc """
  What actually happened when a payment intent was settled: who paid, on which
  chain, and the transaction the facilitator reported.

  One receipt per intent, held by a unique index on the intent. The unique
  transaction hash, where one came back, also stops the same payment being
  recorded twice if a call is retried. A receipt is written only for an intent
  of this site that is waiting on its settlement. A receipt is read only by the
  payer of its intent, and only on the site that offered it.
  """

  use Ash.Resource,
    otp_app: :regent_payments,
    domain: RegentPayments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Expr

  postgres do
    repo &RegentPayments.repo/2
    schema "regent_payments"
    table "payment_receipts"
    migrate? false
  end

  attributes do
    uuid_primary_key :id

    attribute :payer_address, :string, allow_nil?: false, public?: true
    attribute :network, :string, allow_nil?: false, public?: true
    attribute :asset, :string, allow_nil?: false, public?: true
    attribute :amount_atomic, :integer, allow_nil?: false, public?: true

    # Which facilitator verified and settled this payment, so a later
    # reconciliation knows whose records to go and read.
    attribute :facilitator, :string, allow_nil?: false, public?: true

    # Absent when the facilitator settled without naming a transaction.
    attribute :transaction_hash, :string, allow_nil?: true, public?: true

    # The facilitator's answer, kept whole and unedited.
    attribute :payment_response, :map, allow_nil?: false, public?: true

    attribute :settled_at, :utc_datetime_usec, allow_nil?: false, public?: true

    timestamps()
  end

  identities do
    identity :unique_payment_intent, [:payment_intent_id], eager_check?: false
    identity :unique_transaction_hash, [:transaction_hash], eager_check?: false
  end

  relationships do
    belongs_to :payment_intent, RegentPayments.PaymentIntent, allow_nil?: false, public?: true
  end

  preparations do
    prepare {RegentPayments.Preparations.ThisSite, through: :payment_intent}
  end

  actions do
    defaults [:read]

    read :settled_for_targets do
      description "The settled payments of one kind made for any of the given targets."
      argument :kind, :atom, allow_nil?: false
      argument :target_ids, {:array, :uuid}, allow_nil?: false

      filter expr(
               payment_intent.kind == ^arg(:kind) and
                 payment_intent.target_id in ^arg(:target_ids)
             )
    end

    read :settled_by_party do
      description "The settled payments of one kind a profile made or was the target of."
      argument :kind, :atom, allow_nil?: false
      argument :profile_id, :uuid, allow_nil?: false

      filter expr(
               payment_intent.kind == ^arg(:kind) and
                 (payment_intent.actor_profile_id == ^arg(:profile_id) or
                    payment_intent.target_id == ^arg(:profile_id))
             )
    end

    create :record do
      description "Writes down a settled payment exactly as the facilitator reported it."

      accept [
        :payment_intent_id,
        :payer_address,
        :network,
        :asset,
        :amount_atomic,
        :facilitator,
        :transaction_hash,
        :payment_response,
        :settled_at
      ]

      change RegentPayments.Changes.SettlingIntent
    end
  end

  policies do
    # Only the library writes a receipt, from what the facilitator answered
    # (`RegentPayments.Steps`); a site cannot write one of its own.
    policy action(:record) do
      forbid_unless context_equals(:regent_payments, :purchase)
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(payment_intent.actor_profile_id == ^actor(:id))
    end
  end
end
