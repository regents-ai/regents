defmodule AshPlatform.AgentAuth.AgentIdentity do
  @moduledoc false

  @enforce_keys [
    :agent_id,
    :registry_address,
    :token_id,
    :wallet,
    :regent_id,
    :agent_link_id,
    :audience
  ]
  defstruct [
    :agent_id,
    :registry_address,
    :token_id,
    :wallet,
    :regent_id,
    :agent_link_id,
    :audience,
    chain_id: 8453,
    role: :agent
  ]
end
