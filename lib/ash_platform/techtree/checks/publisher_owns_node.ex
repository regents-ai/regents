defmodule AshPlatform.Techtree.Checks.PublisherOwnsNode do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  alias AshPlatform.AgentAuth.AgentIdentity

  @impl true
  def describe(_opts), do: "actor is the current publisher of the public node"

  @impl true
  def match?(%AgentIdentity{} = actor, %{subject: subject}, _opts) do
    node_id = subject_node_id(subject)
    authorized?(actor, node_id)
  end

  def match?(_actor, _context, _opts), do: false

  def authorized?(%AgentIdentity{} = actor, node_id), do: owns_node?(actor, node_id)
  def authorized?(_actor, _node_id), do: false

  defp subject_node_id(%Ash.Changeset{} = changeset) do
    Ash.Changeset.get_argument(changeset, :node_id) ||
      Ash.Changeset.get_attribute(changeset, :node_id)
  end

  defp subject_node_id(%Ash.ActionInput{} = input),
    do: Ash.ActionInput.get_argument(input, :node_id)

  defp subject_node_id(_subject), do: nil

  defp owns_node?(%AgentIdentity{} = actor, node_id) when is_binary(node_id) do
    params = [
      Ecto.UUID.dump!(node_id),
      Ecto.UUID.dump!(actor.agent_link_id),
      Ecto.UUID.dump!(actor.regent_id),
      actor.agent_id,
      actor.registry_address,
      actor.token_id,
      actor.wallet,
      actor.chain_id
    ]

    case Ecto.Adapters.SQL.query(
           AshPlatform.Repo,
           """
           SELECT 1
           FROM techtree.nodes AS node
           JOIN agent_links AS link ON link.id = $2
           WHERE node.id = $1
             AND node.workflow_state = 'published'
             AND node.published_at IS NOT NULL
             AND node.publisher_agent_id IS NOT NULL
             AND node.publisher_registry_address IS NOT NULL
             AND node.publisher_token_id IS NOT NULL
             AND node.publisher_wallet IS NOT NULL
             AND node.publisher_chain_id IS NOT NULL
             AND node.publisher_regent_id IS NOT NULL
             AND node.publisher_agent_id = $4
             AND node.publisher_registry_address = $5
             AND node.publisher_token_id = $6
             AND node.publisher_wallet = $7
             AND node.publisher_chain_id = $8
             AND node.publisher_regent_id = $3
             AND link.regent_id = $3
             AND link.agent_id = $4
             AND link.registry_address = $5
             AND link.token_id = $6
             AND link.wallet = $7
           """,
           params
         ) do
      {:ok, %{rows: [[1]]}} -> true
      _result -> false
    end
  rescue
    _error -> false
  end

  defp owns_node?(_actor, _node_id), do: false
end
