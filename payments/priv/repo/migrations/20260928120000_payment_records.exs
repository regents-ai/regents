defmodule RegentPayments.Migrations.PaymentRecords do
  use Ecto.Migration

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS regent_payments")

    create table(:payment_intents, prefix: "regent_payments", primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:site, :text, null: false)
      add(:payment_identifier, :text, null: false)
      add(:kind, :text, null: false)
      add(:actor_profile_id, :uuid, null: false)
      add(:target_type, :text, null: false)
      add(:target_id, :uuid, null: false)
      add(:amount_atomic, :bigint, null: false)
      add(:asset, :text, null: false)
      add(:network, :text, null: false)
      add(:payload, :map, null: false)
      add(:payload_digest, :text, null: false)
      add(:recipient_snapshot, {:array, :map}, null: false)
      add(:effect_summary, :text, null: false)
      add(:status, :text, null: false, default: "prepared")
      add(:expires_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payment_intents, [:payment_identifier],
             prefix: "regent_payments",
             name: :payment_intents_unique_payment_identifier_index
           )

    create index(:payment_intents, [:site, :actor_profile_id, :kind],
             prefix: "regent_payments",
             name: :payment_intents_payer_index
           )

    create table(:payment_receipts, prefix: "regent_payments", primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))

      add(
        :payment_intent_id,
        references(:payment_intents,
          type: :uuid,
          prefix: "regent_payments",
          name: :payment_receipts_payment_intent_id_fkey
        ),
        null: false
      )

      add(:payment_identifier, :text, null: false)
      add(:payer_address, :text, null: false)
      add(:network, :text, null: false)
      add(:asset, :text, null: false)
      add(:amount_atomic, :bigint, null: false)
      add(:facilitator, :text, null: false)
      add(:transaction_hash, :text)
      add(:payment_response, :map, null: false)
      add(:settled_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payment_receipts, [:payment_intent_id],
             prefix: "regent_payments",
             name: :payment_receipts_unique_payment_intent_index
           )

    create unique_index(:payment_receipts, [:payment_identifier],
             prefix: "regent_payments",
             name: :payment_receipts_unique_payment_identifier_index
           )

    create unique_index(:payment_receipts, [:transaction_hash],
             prefix: "regent_payments",
             name: :payment_receipts_unique_transaction_hash_index
           )
  end

  def down do
    raise "Payment records are retained evidence of money that moved; restore a reviewed recovery copy instead."
  end
end
