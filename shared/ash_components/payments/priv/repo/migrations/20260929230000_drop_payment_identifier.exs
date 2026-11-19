defmodule RegentPayments.Migrations.DropPaymentIdentifier do
  @moduledoc """
  A payment is known by its intent's own id. The separate payment identifier
  only ever copied that id, and it went with the x402 extension that named it.
  """

  use Ecto.Migration

  def up do
    drop(
      index(:payment_receipts, [:payment_identifier],
        prefix: "regent_payments",
        name: :payment_receipts_unique_payment_identifier_index
      )
    )

    drop(
      index(:payment_intents, [:payment_identifier],
        prefix: "regent_payments",
        name: :payment_intents_unique_payment_identifier_index
      )
    )

    alter table(:payment_receipts, prefix: "regent_payments") do
      remove(:payment_identifier)
    end

    alter table(:payment_intents, prefix: "regent_payments") do
      remove(:payment_identifier)
    end
  end

  def down do
    raise "Payment records are retained evidence of money that moved; restore a reviewed recovery copy instead."
  end
end
