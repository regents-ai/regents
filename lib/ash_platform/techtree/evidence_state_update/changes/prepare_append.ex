defmodule AshPlatform.Techtree.EvidenceStateUpdate.Changes.PrepareAppend do
  use Ash.Resource.Change

  alias AshPlatform.AgentAuth.AgentIdentity

  @lock_query """
  SELECT id::text, workflow_state, published_at
  FROM techtree.nodes
  WHERE id = ANY($1::uuid[])
  ORDER BY id
  FOR UPDATE
  """

  @impl true
  def change(changeset, _opts, %{actor: %AgentIdentity{} = actor}) do
    changeset
    |> Ash.Changeset.change_attribute(:submitter_agent_id, actor.agent_id)
    |> Ash.Changeset.change_attribute(:submitter_registry_address, actor.registry_address)
    |> Ash.Changeset.change_attribute(:submitter_token_id, actor.token_id)
    |> Ash.Changeset.change_attribute(:submitter_wallet, actor.wallet)
    |> Ash.Changeset.change_attribute(:submitter_chain_id, actor.chain_id)
    |> Ash.Changeset.change_attribute(:submitter_regent_id, actor.regent_id)
    |> Ash.Changeset.change_attribute(
      :siwa_envelope,
      Ash.Changeset.get_argument(changeset, :siwa_envelope)
    )
    |> Ash.Changeset.before_action(&lock_and_validate/1)
  end

  def change(changeset, _opts, _context), do: changeset

  defp lock_and_validate(changeset) do
    node_id = Ash.Changeset.get_attribute(changeset, :node_id)
    reference_ids = Ash.Changeset.get_attribute(changeset, :evidence_reference_ids) || []

    if node_id in reference_ids do
      invalid_reference(changeset)
    else
      case lock_nodes([node_id | reference_ids]) do
        {:ok, nodes} ->
          validate_nodes(changeset, node_id, reference_ids, nodes)

        {:error, _reason} ->
          Ash.Changeset.add_error(changeset, message: "temporary database error")
      end
    end
  end

  defp validate_nodes(changeset, node_id, reference_ids, nodes) do
    case Map.get(nodes, node_id) do
      %{workflow_state: "published", published_at: published_at} when not is_nil(published_at) ->
        if Enum.all?(reference_ids, &public_node?(&1, nodes)),
          do: changeset,
          else: invalid_reference(changeset)

      _node ->
        invalid_reference(changeset)
    end
  end

  defp public_node?(id, nodes) do
    case Map.get(nodes, id) do
      %{workflow_state: "published", published_at: published_at} when not is_nil(published_at) ->
        true

      _node ->
        false
    end
  end

  defp invalid_reference(changeset),
    do: Ash.Changeset.add_error(changeset, message: "invalid_evidence_reference")

  defp lock_nodes(ids) do
    with {:ok, ids} <- dump_ids(ids),
         {:ok, result} <- Ecto.Adapters.SQL.query(AshPlatform.Repo, @lock_query, [ids]) do
      {:ok,
       Map.new(result.rows, fn [id, workflow_state, published_at] ->
         {id, %{workflow_state: workflow_state, published_at: published_at}}
       end)}
    end
  rescue
    _error -> {:error, :invalid_uuid}
  end

  defp dump_ids(ids) do
    ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, dumped} ->
      case Ecto.UUID.dump(id) do
        {:ok, value} -> {:cont, {:ok, [value | dumped]}}
        :error -> {:halt, {:error, :invalid_uuid}}
      end
    end)
    |> case do
      {:ok, dumped} -> {:ok, Enum.reverse(dumped)}
      error -> error
    end
  end
end
