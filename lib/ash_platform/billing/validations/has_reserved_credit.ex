defmodule AshPlatform.Billing.Validations.HasReservedCredit do
  use Ash.Resource.Validation
  import Ash.Expr

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(_, _, _), do: :ok

  @impl true
  def atomic(_, _, _) do
    {:atomic, [:reserved_cents], expr(reserved_cents < ^arg(:amount_cents)),
     expr(error(^InvalidChanges, %{message: "insufficient reserved credit"}))}
  end
end
