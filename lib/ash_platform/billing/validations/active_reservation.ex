defmodule AshPlatform.Billing.Validations.ActiveReservation do
  use Ash.Resource.Validation
  import Ash.Expr

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(_, _, _), do: :ok

  @impl true
  def atomic(_, _, _) do
    {:atomic, [:status], expr(status != :active),
     expr(error(^InvalidChanges, %{message: "reservation is terminal"}))}
  end
end
