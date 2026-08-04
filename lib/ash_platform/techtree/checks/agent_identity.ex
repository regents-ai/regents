defmodule AshPlatform.Techtree.Checks.AgentIdentity do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  alias AshPlatform.AgentAuth.AgentIdentity

  @impl true
  def describe(_opts), do: "actor is a verified, paired agent"

  @impl true
  def match?(%AgentIdentity{} = actor, _context, _opts) do
    params = [
      Ecto.UUID.dump!(actor.agent_link_id),
      Ecto.UUID.dump!(actor.regent_id),
      actor.agent_id,
      actor.registry_address,
      actor.token_id,
      actor.wallet
    ]

    result =
      Ecto.Adapters.SQL.query(
        AshPlatform.Repo,
        """
        SELECT 1
        FROM agent_links
        WHERE id = $1
          AND regent_id = $2
          AND agent_id = $3
          AND registry_address = $4
          AND token_id = $5
          AND wallet = $6
        """,
        params
      )

    match?({:ok, %{rows: [[1]]}}, result)
  rescue
    _error -> false
  end

  def match?(_actor, _context, _opts), do: false
end
