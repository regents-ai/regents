defmodule AshPlatform.Billing.Validations.ReservationCanConsume do
  use Ash.Resource.Validation
  import Ash.Expr

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(_, _, _), do: :ok

  @impl true
  def atomic(_, _, _) do
    {:atomic, [:status, :consumed_cents, :amount_cents],
     expr(status != :active or consumed_cents + ^arg(:amount_cents) > amount_cents),
     expr(
       error(^InvalidChanges, %{
         message: "reservation is terminal or has insufficient remaining credit"
       })
     )}
  end
end
