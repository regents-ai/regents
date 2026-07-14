defmodule AshPlatform.Discussions.CommentReaction.Changes.ValidateComment do
  use Ash.Resource.Change

  alias AshPlatform.Actors.System
  alias AshPlatform.Discussions

  @impl true
  def change(changeset, _opts, _context) do
    comment_id = Ash.Changeset.get_argument(changeset, :comment_id)

    case Discussions.get_comment_audit(comment_id, actor: %System{}) do
      {:ok, %{target_type: :techtree_node, deleted_at: nil}} ->
        changeset

      _other ->
        Ash.Changeset.add_error(changeset,
          field: :comment_id,
          message: "is not an active Techtree comment"
        )
    end
  end
end
