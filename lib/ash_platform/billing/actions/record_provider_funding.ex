defmodule AshPlatform.Billing.Actions.RecordProviderFunding do
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context),
    do: AshPlatform.Billing.Kernel.record_provider_funding(input, context.actor)
end
