defmodule RegentPayments.Types.PaymentIntentStatus do
  @moduledoc "Where one payment intent stands, from terms offered to the effect carried out."
  use Ash.Type.Enum,
    values: [
      :prepared,
      :payment_required,
      :settlement_pending,
      :settled,
      :applied,
      :expired,
      :failed
    ]
end
