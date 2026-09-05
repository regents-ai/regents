defmodule AshPlatform.Discussions.Comment.Changes.Broadcast do
  use Ash.Resource.Change

  alias AshPlatform.Discussions

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
      case result do
        {:ok, comment} ->
          Phoenix.PubSub.broadcast(
            AshPlatform.PubSub,
            Discussions.comment_topic(comment.target_type, comment.target_id),
            {:comments_changed, comment.target_type, comment.target_id}
          )

        {:error, _error} ->
          :ok
      end

      result
    end)
  end
end
