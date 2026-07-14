defmodule AshPlatform.Discussions.CommentReaction.Changes.Broadcast do
  use Ash.Resource.Change

  alias AshPlatform.Actors.System
  alias AshPlatform.Discussions

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn changeset, result ->
      if successful?(result) do
        comment_id = comment_id(changeset, result)

        with {:ok, comment} when not is_nil(comment) <-
               Discussions.get_comment_audit(comment_id, actor: %System{}) do
          Phoenix.PubSub.broadcast(
            AshPlatform.PubSub,
            Discussions.comment_topic(comment.target_type, comment.target_id),
            {:comment_reactions_changed, comment.target_type, comment.target_id}
          )
        end
      end

      result
    end)
  end

  defp successful?({:ok, _record}), do: true
  defp successful?(:ok), do: true
  defp successful?(_result), do: false

  defp comment_id(_changeset, {:ok, reaction}), do: reaction.comment_id
  defp comment_id(changeset, :ok), do: changeset.data.comment_id
end
