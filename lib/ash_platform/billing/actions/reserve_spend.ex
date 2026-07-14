defmodule AshPlatform.Billing.Actions.ReserveSpend do
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context),
    do: AshPlatform.Billing.Kernel.reserve_spend(input, context.actor)
end
