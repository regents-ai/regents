defmodule AshPlatform.Techtree.Edge.Changes.ValidateTopology do
  use Ash.Resource.Change

  alias AshPlatform.Techtree

  @impl true
  def change(changeset, _opts, _context) do
    from_node_id = Ash.Changeset.get_attribute(changeset, :from_node_id)
    to_node_id = Ash.Changeset.get_attribute(changeset, :to_node_id)
    kind = Ash.Changeset.get_attribute(changeset, :kind)

    cond do
      kind not in [:prerequisite, :related] ->
        Ash.Changeset.add_error(changeset,
          field: :kind,
          message: "must be prerequisite or related"
        )

      from_node_id == to_node_id ->
        Ash.Changeset.add_error(changeset,
          field: :to_node_id,
          message: "must differ from the source node"
        )

      true ->
        validate_nodes(changeset, from_node_id, to_node_id, kind)
    end
  end

  defp validate_nodes(changeset, from_node_id, to_node_id, kind) do
    with {:ok, %{tree_id: tree_id}} <- Techtree.get_public_node(from_node_id),
         {:ok, %{tree_id: ^tree_id}} <- Techtree.get_public_node(to_node_id) do
      validate_cycle(changeset, from_node_id, to_node_id, tree_id, kind)
    else
      _result ->
        Ash.Changeset.add_error(changeset,
          field: :to_node_id,
          message: "must belong to the same tree as the source node"
        )
    end
  end

  defp validate_cycle(changeset, _from_node_id, _to_node_id, _tree_id, :related),
    do: changeset

  defp validate_cycle(changeset, from_node_id, to_node_id, tree_id, :prerequisite) do
    case Techtree.list_tree_edges(tree_id) do
      {:ok, edges} ->
        if creates_cycle?(from_node_id, to_node_id, edges) do
          Ash.Changeset.add_error(changeset,
            field: :to_node_id,
            message: "would create a prerequisite cycle"
          )
        else
          changeset
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp creates_cycle?(from_node_id, to_node_id, edges) do
    ancestors_by_node =
      edges
      |> Enum.filter(&(&1.kind == :prerequisite))
      |> Enum.group_by(& &1.to_node_id, & &1.from_node_id)

    ancestor?(to_node_id, from_node_id, ancestors_by_node, MapSet.new())
  end

  defp ancestor?(candidate_id, candidate_id, _ancestors_by_node, _visited), do: true

  defp ancestor?(candidate_id, node_id, ancestors_by_node, visited) do
    if MapSet.member?(visited, node_id) do
      false
    else
      visited = MapSet.put(visited, node_id)

      ancestors_by_node
      |> Map.get(node_id, [])
      |> Enum.any?(&ancestor?(candidate_id, &1, ancestors_by_node, visited))
    end
  end
end
