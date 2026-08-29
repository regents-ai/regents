defmodule AshPlatform.Autolaunch.LaunchDraft.Validations.LegacyRegentProvenance do
  @moduledoc false
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute
  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch

  @impl true
  def validate(%{data: %{id: draft_id}}, _opts, %{actor: %Human{} = actor}) do
    case Autolaunch.get_my_launch_draft(draft_id, actor: actor) do
      {:ok, %{regent_id: regent_id}} when is_binary(regent_id) -> :ok
      _not_legacy -> legacy_only()
    end
  end

  def validate(_changeset, _opts, _context), do: legacy_only()

  defp legacy_only do
    {:error,
     InvalidAttribute.exception(
       field: :image,
       message: "external image URLs are available only to legacy Regent-linked drafts"
     )}
  end
end
