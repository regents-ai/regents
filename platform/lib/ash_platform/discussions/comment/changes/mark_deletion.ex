defmodule AshPlatform.Discussions.Comment.Changes.MarkDeletion do
  use Ash.Resource.Change

  alias AshPlatform.Actors.Human

  @impl true
  def change(
        %{data: %{author_id: author_id}} = changeset,
        _opts,
        %{actor: %Human{human_account_id: human_account_id}}
      )
      when is_integer(human_account_id) do
    authority = if author_id == human_account_id, do: :author, else: :admin

    Ash.Changeset.force_change_attributes(changeset, %{
      deleted_at: DateTime.utc_now(),
      deleted_by_human_account_id: human_account_id,
      deletion_authority: authority
    })
  end

  def change(changeset, _opts, _context), do: changeset
end
