defmodule Regents.Keyfleet.Fleets.Validations.SameDeployment do
  @moduledoc """
  A fleet is bound to one deployment for good: an unbound fleet takes any
  deployment, a bound one only the deployment it already has.

  It runs inside the action's transaction and compares against the fleet as
  committed, read under its row lock, so of two recordings of one fleet at the
  same moment, the second waits for the first to commit and then sees what it
  bound.
  """
  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    id = changeset.data.id

    changeset.resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!()
    |> compare(changeset)
  end

  defp compare(%{manager_address: nil}, _changeset), do: :ok

  defp compare(fleet, changeset) do
    if Enum.all?(
         changeset.resource.deployment_fields(),
         &(Map.fetch!(fleet, &1) == Ash.Changeset.get_attribute(changeset, &1))
       ) do
      :ok
    else
      {:error, field: :manager_address, message: "fleet is already bound to another deployment"}
    end
  end
end
