defmodule Regents.Blog.Changes.Publish do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    authors = Ash.Changeset.get_attribute(changeset, :authors) || []

    changeset =
      case authors do
        [first | _] ->
          changeset
          |> Ash.Changeset.force_change_attribute(:author, first.name)
          |> Ash.Changeset.force_change_attribute(:author_x, first.x)

        _ ->
          Ash.Changeset.add_error(changeset, field: :authors, message: "Add at least one author.")
      end

    title = Ash.Changeset.get_attribute(changeset, :title)
    alt = Ash.Changeset.get_attribute(changeset, :cover_alt)

    changeset
    |> Ash.Changeset.force_change_attribute(:slug, Ecto.UUID.generate())
    |> Ash.Changeset.force_change_attribute(
      :published_by,
      Map.get(context.actor || %{}, :human_account_id)
    )
    |> Ash.Changeset.force_change_attribute(
      :cover_alt,
      if(alt in [nil, ""], do: title, else: alt)
    )
    |> Ash.Changeset.force_change_attribute(:draft, false)
  end
end
