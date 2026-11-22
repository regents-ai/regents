defmodule Regents.Keyfleet.Keys.Changes.TellKeysChanged do
  @moduledoc """
  Once a change to which Key an agent is on, or which Key a person writes as,
  is saved, the fleet's pages, readings and agents' live feeds hear which Keys
  it changed, as the chain's changes are heard
  (`Regents.Keyfleet.Keys.topic/1`'s `{:keys_changed, fleet_id, token_ids}`): the Key
  the agent is on or came off, or the Key the person chose, and the Key the
  agent left when it moved (`:left_token_id` in the change's context, from
  `Regents.Keyfleet.Keys.Changes.PutAgent`). A change that wasn't saved tells nobody.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn changeset, result ->
      with {:ok, %{fleet_id: fleet_id, token_id: token_id}} <- saved(changeset, result) do
        token_ids = Enum.uniq([token_id | List.wrap(changeset.context[:left_token_id])])

        Phoenix.PubSub.broadcast(
          Regents.PubSub,
          Regents.Keyfleet.Keys.topic(fleet_id),
          {:keys_changed, fleet_id, token_ids}
        )
      end

      result
    end)
  end

  # A put answers the row it saved; a release, the row it took away.
  defp saved(_changeset, {:ok, %{} = row}), do: {:ok, row}
  defp saved(%{action_type: :destroy, data: row}, :ok), do: {:ok, row}
  defp saved(_changeset, error), do: error
end
