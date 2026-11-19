defmodule RegentPayments.Migrations.ReceiptsPaidWith do
  @moduledoc """
  A payment is paid either in USDC from the payer's wallet or in Regent
  Credits. A USDC receipt names the wallet that paid, the chain, the asset and
  the facilitator that settled it; a Credits receipt has none of those, and
  names its Credits hold in the payment response instead. Every receipt
  written before this was paid in USDC, so the column arrives filled with
  "usdc" and then loses its default, without rewriting a row.
  """

  use Ecto.Migration

  def up do
    alter table(:payment_receipts, prefix: "regent_payments") do
      add(:paid_with, :text, null: false, default: "usdc")
    end

    alter table(:payment_receipts, prefix: "regent_payments") do
      modify(:paid_with, :text, default: nil)
      modify(:payer_address, :text, null: true)
      modify(:network, :text, null: true)
      modify(:asset, :text, null: true)
      modify(:facilitator, :text, null: true)
    end

    create constraint(:payment_receipts, :paid_with_names_how,
             prefix: "regent_payments",
             check: """
             (paid_with = 'usdc' AND payer_address IS NOT NULL AND network IS NOT NULL
               AND asset IS NOT NULL AND facilitator IS NOT NULL)
             OR (paid_with = 'credits' AND payer_address IS NULL AND network IS NULL
               AND asset IS NULL AND facilitator IS NULL AND transaction_hash IS NULL)
             """
           )
  end

  def down do
    raise "Payment records are retained evidence of money that moved; restore a reviewed recovery copy instead."
  end
end
