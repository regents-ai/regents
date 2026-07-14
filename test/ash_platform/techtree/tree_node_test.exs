defmodule AshPlatform.Techtree.TreeNodeTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Techtree

  @root_names [
    "GeneBench-Pro Reference Lab",
    "Question Forge Metaskills",
    "New Question Candidates",
    "BixBench Capsule Lab",
    "Skill Training Lab"
  ]

  test "the five founder roots are idempotent and returned in canonical order" do
    assert :ok = Techtree.ensure_seed_trees(actor: %System{})
    assert :ok = Techtree.ensure_seed_trees(actor: %System{})

    assert {:ok, trees} = Techtree.list_trees()
    assert Enum.map(trees, & &1.name) == @root_names
    assert length(Enum.uniq_by(trees, & &1.slug)) == 5
  end

  test "a system import creates an arbitrary public node behind named reads" do
    tree = Techtree.get_tree_by_slug!("bixbench-capsule-lab")

    assert {:ok, node} =
             Techtree.import_public_node(
               tree.id,
               "BBH reference 001",
               "A reference item from the BBH training corpus.",
               "sha256:abc123",
               actor: %System{}
             )

    assert node.tree_id == tree.id
    assert {:ok, [listed]} = Techtree.list_tree_nodes(tree.id)
    assert listed.id == node.id

    assert {:ok, public} = Techtree.get_public_node(node.id)
    assert public.title == "BBH reference 001"
    assert public.payload_hash == "sha256:abc123"
    assert {:ok, nil} = Techtree.get_public_node(Ash.UUID.generate())
  end

  test "the public listing interface needs no actor or filter and sorts newest first" do
    tree = Techtree.get_tree_by_slug!("new-question-candidates")

    older =
      Techtree.import_public_node!(tree.id, "Older public node", nil, nil, actor: %System{})

    newer =
      Techtree.import_public_node!(tree.id, "Newer public node", nil, nil, actor: %System{})

    assert {:ok, nodes} = Techtree.list_public_nodes(actor: nil)
    assert Enum.take(Enum.map(nodes, & &1.id), 2) == [newer.id, older.id]
  end

  test "the public listing interface sorts equal publication times by id" do
    tree = Techtree.get_tree_by_slug!("genebench-pro-reference-lab")

    first = Techtree.import_public_node!(tree.id, "Tie one", nil, nil, actor: %System{})
    second = Techtree.import_public_node!(tree.id, "Tie two", nil, nil, actor: %System{})
    published_at = DateTime.utc_now() |> DateTime.add(60, :second)

    for node <- [first, second] do
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        "UPDATE techtree.nodes SET published_at = $1 WHERE id = $2",
        [published_at, Ecto.UUID.dump!(node.id)]
      )
    end

    assert {:ok, nodes} = Techtree.list_public_nodes(actor: nil)

    assert Enum.take(Enum.map(nodes, & &1.id), 2) ==
             Enum.sort([first.id, second.id])
  end

  test "tree and node writes reject missing, human, and lookalike system actors" do
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    for actor <- [nil, %{role: :system}, %{role: :human, human_account_id: 1}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Techtree.import_public_node(
                 tree.id,
                 "Forbidden",
                 nil,
                 nil,
                 actor: actor
               )
    end
  end
end
