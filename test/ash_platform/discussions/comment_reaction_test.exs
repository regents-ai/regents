defmodule AshPlatform.Discussions.CommentReactionTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch, Discussions, Techtree}
  alias AshPlatform.Actors.{Human, System}

  test "one signed human sets, changes, and removes one reaction per Techtree comment" do
    {node, account} = fixture!()

    actor = %Human{human_account_id: account.id}

    comment =
      Discussions.post_comment!(
        :techtree_node,
        node.id,
        "Evidence worth reviewing",
        Ash.UUID.generate(),
        actor: actor
      )

    useful = Discussions.set_comment_reaction!(comment.id, :useful, actor: actor)
    assert useful.value == :useful

    negative = Discussions.set_comment_reaction!(comment.id, :negative, actor: actor)
    assert negative.id == useful.id
    assert negative.value == :negative

    assert [current] = Discussions.list_comment_reactions!([comment.id])
    assert current.id == useful.id
    assert current.reactor_id == account.id

    assert :ok = Discussions.remove_comment_reaction!(negative, actor: actor)
    assert Discussions.list_comment_reactions!([comment.id]) == []
  end

  test "only the signed owner may remove and only active Techtree comments accept reactions" do
    {node, owner} = fixture!()
    other = account!("0x2222222222222222222222222222222222222222")
    owner_actor = human(owner)
    comment = post!(:techtree_node, node.id, owner_actor)

    for actor <- [nil, %{human_account_id: owner.id}, %System{}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Discussions.set_comment_reaction(comment.id, :useful, actor: actor)
    end

    reaction = Discussions.set_comment_reaction!(comment.id, :useful, actor: owner_actor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Discussions.remove_comment_reaction(reaction, actor: human(other))

    Discussions.delete_comment!(comment, actor: owner_actor)

    assert {:error, %Ash.Error.Invalid{}} =
             Discussions.set_comment_reaction(comment.id, :negative, actor: owner_actor)

    auction =
      Autolaunch.import_auction!("No reactions", nil, false, :created, nil, actor: %System{})

    auction_comment = post!(:autolaunch_auction, auction.id, owner_actor)

    assert {:error, %Ash.Error.Invalid{}} =
             Discussions.set_comment_reaction(auction_comment.id, :off_topic, actor: owner_actor)
  end

  test "setting and removing a reaction broadcasts the owning Techtree target" do
    {node, account} = fixture!()
    actor = human(account)
    comment = post!(:techtree_node, node.id, actor)
    node_id = node.id

    Phoenix.PubSub.subscribe(
      AshPlatform.PubSub,
      Discussions.comment_topic(:techtree_node, node.id)
    )

    reaction = Discussions.set_comment_reaction!(comment.id, :useful, actor: actor)
    assert_receive {:comment_reactions_changed, :techtree_node, ^node_id}

    Discussions.remove_comment_reaction!(reaction, actor: actor)
    assert_receive {:comment_reactions_changed, :techtree_node, ^node_id}
  end

  defp fixture! do
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    node =
      Techtree.import_public_node!(tree.id, "Reaction target", nil, nil, actor: %System{})

    {node, account!("0x1111111111111111111111111111111111111111")}
  end

  defp account!(wallet) do
    Accounts.register_verified!(
      "did:privy:reaction:#{Elixir.System.unique_integer([:positive])}",
      wallet,
      [wallet],
      actor: %System{}
    )
  end

  defp human(account), do: %Human{human_account_id: account.id}

  defp post!(target_type, target_id, actor) do
    Discussions.post_comment!(
      target_type,
      target_id,
      "Evidence worth reviewing",
      Ash.UUID.generate(),
      actor: actor
    )
  end
end
