defmodule AshPlatform.Billing.Actions.CreditSummary do
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context),
    do: AshPlatform.Billing.Kernel.credit_summary(input, context.actor)
end
