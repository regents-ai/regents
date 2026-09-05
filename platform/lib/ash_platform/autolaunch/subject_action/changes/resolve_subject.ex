defmodule AshPlatform.Autolaunch.SubjectAction.Changes.ResolveSubject do
  use Ash.Resource.Change

  alias AshPlatform.Autolaunch

  @impl true
  def change(changeset, _opts, _context) do
    subject_identity = Ash.Changeset.get_argument(changeset, :subject_identity)

    apply_lookup_result(changeset, Autolaunch.get_public_subject(subject_identity))
  end

  @doc false
  def apply_lookup_result(changeset, {:ok, %{id: id}}) do
    Ash.Changeset.change_attribute(changeset, :subject_id, id)
  end

  def apply_lookup_result(changeset, {:ok, nil}) do
    Ash.Changeset.add_error(changeset,
      field: :subject_identity,
      message: "does not identify a public subject"
    )
  end

  def apply_lookup_result(changeset, {:error, error}) do
    Ash.Changeset.add_error(changeset, error)
  end
end
