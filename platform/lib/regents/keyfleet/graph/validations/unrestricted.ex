defmodule Regents.Keyfleet.Graph.Validations.Unrestricted do
  @moduledoc """
  The actor's Key in the fleet, the one it is a member as
  (`Regents.Keyfleet.Graph.Checks.KeyActor.membership/3`), is not one whose edits a
  vote of the fleet has restricted. For changes that name no Key. Who is a
  member at all is the policy's to say.
  """
  use Ash.Resource.Validation

  alias Regents.Keyfleet.Graph.Checks.KeyActor
  alias Regents.Keyfleet.Graph.Errors.EditsRestrictedError

  @impl true
  def validate(changeset, _opts, %{actor: actor}) do
    fleet_id = Ash.Changeset.get_argument_or_attribute(changeset, :fleet_id)
    within = Application.fetch_env!(:regents, :keyfleet_graph)[:check_timeout]

    case KeyActor.membership(actor, fleet_id, within) do
      {:ok, %{restricted?: true, token_id: token_id}} ->
        {:error, EditsRestrictedError.exception(fleet_id: fleet_id, token_id: token_id)}

      _member_or_not ->
        :ok
    end
  end
end
