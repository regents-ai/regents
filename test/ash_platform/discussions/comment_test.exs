defmodule AshPlatform.Discussions.CommentTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Discussions, Techtree}
  alias AshPlatform.Actors.{Human, System}

  @owner_wallet "0x1111111111111111111111111111111111111111"
  @other_wallet "0x2222222222222222222222222222222222222222"
  @admin_wallet "0x3333333333333333333333333333333333333333"

  setup do
    prior = Application.get_env(:ash_platform, :admin_wallet_addresses, [])
    Application.put_env(:ash_platform, :admin_wallet_addresses, [String.downcase(@admin_wallet)])
    on_exit(fn -> Application.put_env(:ash_platform, :admin_wallet_addresses, prior) end)
  end

  test "a signed human posts one idempotent immutable comment and public reads are newest-first" do
    {node, owner, _other, _admin} = fixture!()
    actor = human(owner)
    request_id = Ash.UUID.generate()

    assert {:ok, first} =
             Discussions.post_comment(
               :techtree_node,
               node.id,
               "First **comment**",
               request_id,
               actor: actor
             )

    assert {:ok, retried} =
             Discussions.post_comment(
               :techtree_node,
               node.id,
               "First **comment**",
               request_id,
               actor: actor
             )

    assert retried.id == first.id

    second =
      Discussions.post_comment!(
        :techtree_node,
        node.id,
        "Second comment",
        Ash.UUID.generate(),
        actor: actor
      )

    assert {:ok, comments} = Discussions.list_comments(:techtree_node, node.id)
    assert Enum.map(comments, & &1.id) == [second.id, first.id]
    assert hd(comments).author.id == owner.id
    assert Ash.Resource.Info.action(AshPlatform.Discussions.Comment, :update) == nil
  end

  test "an idempotency key cannot be reused for different comment content" do
    {node, owner, _other, _admin} = fixture!()
    actor = human(owner)
    request_id = Ash.UUID.generate()

    assert {:ok, _comment} =
             Discussions.post_comment(
               :techtree_node,
               node.id,
               "Original comment",
               request_id,
               actor: actor
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Discussions.post_comment(
               :techtree_node,
               node.id,
               "Changed comment",
               request_id,
               actor: actor
             )
  end

  test "target existence, exact human principal, and comment content are enforced" do
    {node, owner, _other, _admin} = fixture!()

    assert {:error, %Ash.Error.Invalid{}} =
             Discussions.post_comment(
               :techtree_node,
               Ash.UUID.generate(),
               "Missing target",
               Ash.UUID.generate(),
               actor: human(owner)
             )

    for actor <- [nil, %{role: :human, human_account_id: owner.id}, %System{}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Discussions.post_comment(
                 :techtree_node,
                 node.id,
                 "Nope",
                 Ash.UUID.generate(),
                 actor: actor
               )
    end

    assert {:error, %Ash.Error.Invalid{}} =
             Discussions.post_comment(
               :techtree_node,
               node.id,
               "# Not allowed",
               Ash.UUID.generate(),
               actor: human(owner)
             )
  end

  test "author and configured admin may delete; another human may not; audit remains private" do
    {node, owner, other, admin} = fixture!()

    author_comment = post!(node, owner, "Author removal")

    assert {:error, %Ash.Error.Forbidden{}} =
             Discussions.delete_comment(author_comment, actor: human(other))

    assert {:ok, deleted_by_author} =
             Discussions.delete_comment(author_comment, actor: human(owner))

    assert deleted_by_author.deletion_authority == :author
    assert deleted_by_author.deleted_by_human_account_id == owner.id
    assert deleted_by_author.deleted_at
    assert {:ok, []} = Discussions.list_comments(:techtree_node, node.id)

    assert {:error, _error} =
             Discussions.delete_comment(deleted_by_author, actor: human(owner))

    admin_comment = post!(node, owner, "Admin removal")

    assert {:ok, deleted_by_admin} =
             Discussions.delete_comment(admin_comment, actor: human(admin))

    assert deleted_by_admin.deletion_authority == :admin
    assert deleted_by_admin.deleted_by_human_account_id == admin.id

    assert {:ok, audit} = Discussions.get_comment_audit(admin_comment.id, actor: %System{})
    assert audit.body == "Admin removal"
    assert audit.deleted_at
  end

  test "post and delete broadcast the target after the action transaction" do
    {node, owner, _other, _admin} = fixture!()
    node_id = node.id
    topic = Discussions.comment_topic(:techtree_node, node.id)
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, topic)

    comment = post!(node, owner, "Realtime")
    assert_receive {:comments_changed, :techtree_node, ^node_id}

    Discussions.delete_comment!(comment, actor: human(owner))
    assert_receive {:comments_changed, :techtree_node, ^node_id}
  end

  defp fixture! do
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    node =
      Techtree.import_public_node!(tree.id, "Comment target", nil, "sha256:comment-target",
        actor: %System{}
      )

    {node, account!("owner", @owner_wallet), account!("other", @other_wallet),
     account!("admin", @admin_wallet)}
  end

  defp account!(suffix, wallet) do
    Accounts.register_verified!(
      "did:privy:comment:#{suffix}:#{Elixir.System.unique_integer([:positive])}",
      wallet,
      [wallet],
      actor: %System{}
    )
  end

  defp human(account), do: %Human{human_account_id: account.id}

  defp post!(node, account, body) do
    Discussions.post_comment!(
      :techtree_node,
      node.id,
      body,
      Ash.UUID.generate(),
      actor: human(account)
    )
  end
end
