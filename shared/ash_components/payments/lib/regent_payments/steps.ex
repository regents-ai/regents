defmodule RegentPayments.Steps do
  @moduledoc false

  # The status changes a payment intent goes through and the receipt of its
  # settlement are made here and nowhere else: their policies authorize them
  # only with this context, so a site's own code cannot mark an intent paid or
  # write a receipt with a hash and amount of its choosing.

  alias RegentPayments.PaymentReceipt

  @context %{regent_payments: :purchase}

  @doc "Moves `intent` on by the update `action`, as `actor`."
  def step(intent, action, actor) do
    intent
    |> Ash.Changeset.for_update(action, %{}, actor: actor, context: @context)
    |> Ash.update()
  end

  @doc "Writes down a settlement exactly as the facilitator reported it."
  def record_receipt(attributes, actor) do
    PaymentReceipt
    |> Ash.Changeset.for_create(:record, attributes, actor: actor, context: @context)
    |> Ash.create()
  end
end
