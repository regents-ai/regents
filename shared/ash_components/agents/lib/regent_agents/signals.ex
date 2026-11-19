defmodule RegentAgents.Signals do
  @moduledoc """
  What pairing tells the site, as Ash signals. A site listens with `signals_in`
  on one of its own resources; this library never names the site.

    * `:agent_paired`: an agent paired with `privy_user_id`, through a pairing
      code that person made. `paired_agent_id` names the pairing, and is also
      its row in `regent_agents.pairing_history`, which keeps it after an
      unpair.

  It is emitted inside the pairing's own transaction, after the agent is saved.
  A listener with the default delivery runs in that transaction, so the work it
  queues commits or rolls back with the pairing, and a listener that fails
  refuses the pairing.
  """

  use Ash.Signals

  signals do
    signal :agent_paired do
      argument :paired_agent_id, :uuid, allow_nil?: false
      argument :privy_user_id, :string, allow_nil?: false
    end
  end
end
