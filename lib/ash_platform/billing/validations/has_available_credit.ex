defmodule AshPlatform.Billing.Validations.HasAvailableCredit do
  use Ash.Resource.Validation
  import Ash.Expr

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(_, _, _), do: :ok

  @impl true
  def atomic(_, _, _) do
    {:atomic, [:funded_cents, :reserved_cents, :consumed_cents],
     expr(funded_cents - reserved_cents - consumed_cents < ^arg(:amount_cents)),
     expr(error(^InvalidChanges, %{message: "insufficient available credit"}))}
  end
end
