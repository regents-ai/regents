defmodule AshPlatform.AgentAuth.DeterministicVerificationClient do
  @moduledoc false
  @behaviour AshPlatform.AgentAuth.VerificationClient

  @impl true
  def verify(envelope) do
    if Process.get(:capture_agent_verification_calls, false),
      do: send(self(), {:agent_verification, envelope})

    Process.get(:agent_verification_result, {:error, :verification_failed})
  end
end
