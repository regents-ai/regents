defmodule RegentPayments.Migrations.ReceiptsPaidWithDefault do
  @moduledoc """
  Every payment is in USDC, so a receipt no longer says what it was paid with
  and the library writes no `paid_with`. The column stays, with the receipts
  already written, until a later change drops it. Until then the database
  fills it with "usdc", which keeps `paid_with_names_how` true for every new
  receipt: each one names the wallet that paid, the chain, the asset and the
  facilitator. Only the column's default changes; no row is rewritten.
  """

  use Ecto.Migration

  def change do
    alter table(:payment_receipts, prefix: "regent_payments") do
      modify(:paid_with, :text, default: "usdc", from: {:text, default: nil})
    end
  end
end
