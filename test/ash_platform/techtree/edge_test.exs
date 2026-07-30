defmodule AshPlatform.Techtree.EdgeTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Techtree

  setup do
    assert :ok = Techtree.ensure_seed_trees(actor: %System{})
    :ok
  end

  test "edges default to prerequisite and each ordered pair is unique" do
    [from_node, to_node] = nodes!("question-forge-metaskills", ["From", "To"])

    assert {:ok, edge} = Techtree.create_edge(from_node.id, to_node.id, actor: %System{})
    assert edge.kind == :prerequisite

    assert {:error, %Ash.Error.Invalid{}} =
             Techtree.create_edge(
               from_node.id,
               to_node.id,
               %{kind: :related},
               actor: %System{}
             )

    assert {:ok, [listed]} = Techtree.list_tree_edges(from_node.tree_id)
    assert listed.id == edge.id
  end

  test "self-loops are rejected before persistence" do
    [node] = nodes!("skill-training-lab", ["Solo"])

    assert {:error, error = %Ash.Error.Invalid{}} =
             Techtree.create_edge(node.id, node.id, actor: %System{})

    assert Exception.message(error) =~ "must differ from the source node"
    assert {:ok, []} = Techtree.list_tree_edges(node.tree_id)
  end

  test "an explicit nil kind returns a validation error" do
    [from_node, to_node] = nodes!("question-forge-metaskills", ["Nil from", "Nil to"])

    assert {:error, error = %Ash.Error.Invalid{}} =
             Techtree.create_edge(
               from_node.id,
               to_node.id,
               %{kind: nil},
               actor: %System{}
             )

    assert Exception.message(error) =~ "must be prerequisite or related"
    assert {:ok, []} = Techtree.list_tree_edges(from_node.tree_id)
  end

  test "edge creation requires the exact system actor" do
    [from_node, to_node] = nodes!("skill-training-lab", ["Denied from", "Denied to"])

    for actor <- [nil, %Human{human_account_id: 1}, %{role: :system}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Techtree.create_edge(from_node.id, to_node.id, actor: actor)
    end

    assert {:ok, []} = Techtree.list_tree_edges(from_node.tree_id)
  end

  test "both endpoints must belong to the same tree" do
    [from_node] = nodes!("genebench-pro-reference-lab", ["First tree"])
    [to_node] = nodes!("bixbench-capsule-lab", ["Second tree"])

    assert {:error, error = %Ash.Error.Invalid{}} =
             Techtree.create_edge(from_node.id, to_node.id, actor: %System{})

    assert Exception.message(error) =~ "must belong to the same tree"
    assert {:ok, []} = Techtree.list_tree_edges(from_node.tree_id)
  end

  test "missing endpoint ids return validation errors" do
    [from_node, to_node] = nodes!("genebench-pro-reference-lab", ["Present from", "Present to"])
    missing_id = Ash.UUID.generate()

    for {candidate_from_id, candidate_to_id} <- [
          {missing_id, to_node.id},
          {from_node.id, missing_id}
        ] do
      assert {:error, error = %Ash.Error.Invalid{}} =
               Techtree.create_edge(candidate_from_id, candidate_to_id, actor: %System{})

      assert Exception.message(error) =~ "must belong to the same tree"
    end

    assert {:ok, []} = Techtree.list_tree_edges(from_node.tree_id)
  end

  test "a prerequisite diamond is accepted" do
    [root, left, right, leaf] =
      nodes!("bixbench-capsule-lab", ["Diamond root", "Diamond left", "Diamond right", "Leaf"])

    for {from_node, to_node} <- [
          {root, left},
          {root, right},
          {left, leaf},
          {right, leaf}
        ] do
      assert {:ok, _edge} =
               Techtree.create_edge(from_node.id, to_node.id, actor: %System{})
    end

    assert {:ok, edges} = Techtree.list_tree_edges(root.tree_id)
    assert length(edges) == 4
  end

  test "a reverse related edge is accepted over a prerequisite pair" do
    [first, second] = nodes!("question-forge-metaskills", ["Forward", "Reverse"])

    assert {:ok, prerequisite} =
             Techtree.create_edge(first.id, second.id, actor: %System{})

    assert {:ok, related} =
             Techtree.create_edge(
               second.id,
               first.id,
               %{kind: :related},
               actor: %System{}
             )

    assert prerequisite.kind == :prerequisite
    assert related.kind == :related
    assert {:ok, edges} = Techtree.list_tree_edges(first.tree_id)
    assert length(edges) == 2
  end

  test "a three-node prerequisite cycle is rejected but a related edge is allowed" do
    [first, second, third] =
      nodes!("new-question-candidates", ["First", "Second", "Third"])

    assert {:ok, _edge} = Techtree.create_edge(first.id, second.id, actor: %System{})
    assert {:ok, _edge} = Techtree.create_edge(second.id, third.id, actor: %System{})

    assert {:error, error = %Ash.Error.Invalid{}} =
             Techtree.create_edge(third.id, first.id, actor: %System{})

    assert Exception.message(error) =~ "would create a prerequisite cycle"
    assert {:ok, prerequisite_edges} = Techtree.list_tree_edges(first.tree_id)
    assert length(prerequisite_edges) == 2

    assert {:ok, related} =
             Techtree.create_edge(
               third.id,
               first.id,
               %{kind: :related},
               actor: %System{}
             )

    assert related.kind == :related
    assert {:ok, all_edges} = Techtree.list_tree_edges(first.tree_id)
    assert length(all_edges) == 3
  end

  defp nodes!(tree_slug, titles) do
    tree = Techtree.get_tree_by_slug!(tree_slug)

    Enum.map(titles, fn title ->
      Techtree.import_public_node!(tree.id, title, nil, nil, actor: %System{})
    end)
  end
end
