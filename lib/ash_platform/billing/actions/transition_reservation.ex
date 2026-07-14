defmodule AshPlatform.Billing.Actions.TransitionReservation do
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, opts, context) do
    case opts[:transition] do
      :consume -> AshPlatform.Billing.Kernel.consume(input, context.actor)
      :release -> AshPlatform.Billing.Kernel.close(input, context.actor, :released)
      :expire -> AshPlatform.Billing.Kernel.close(input, context.actor, :expired)
    end
  end
end
