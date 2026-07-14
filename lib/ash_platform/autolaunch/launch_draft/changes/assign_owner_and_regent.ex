defmodule AshPlatform.Autolaunch.LaunchDraft.Changes.AssignOwnerAndRegent do
  use Ash.Resource.Change

  alias AshPlatform.Actors.Human
  alias AshPlatform.Formation

  @impl true
  def change(changeset, _opts, %{actor: %Human{human_account_id: human_account_id} = actor}) do
    case Formation.get_my_regent(actor: actor) do
      {:ok, nil} ->
        Ash.Changeset.add_error(changeset,
          field: :regent_id,
          message: "requires a formed Regent"
        )

      {:ok, regent} ->
        Ash.Changeset.force_change_attributes(changeset, %{
          human_account_id: human_account_id,
          regent_id: regent.id
        })

      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :regent_id,
          message: "could not verify the formed Regent",
          value: error
        )
    end
  end

  def change(changeset, _opts, _context), do: changeset
end
