defmodule Regents.Keyfleet.Projects.Validations.Active do
  @moduledoc """
  The change names one of its fleet's active projects: an archived project
  takes no writes until a Key takes it over (`Regents.Keyfleet.Projects.open/2`).
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)

    with {:ok, _project} <-
           Regents.Keyfleet.Projects.open(
             fleet_id,
             Ash.Changeset.get_attribute(changeset, :project)
           ),
         do: :ok
  end
end
