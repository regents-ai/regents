defmodule Regents.Keyfleet.Graph.Validations.KnownFleet do
  @moduledoc "The request names one of the catalog's fleets, each of which has a workspace."
  use Ash.Resource.Validation

  alias Regents.Keyfleet.Graph.Errors.UnknownFleetError

  @impl true
  def supports(_opts), do: [Ash.ActionInput, Ash.Changeset, Ash.Query]

  @impl true
  def validate(input, _opts, _context) do
    fleet_id = fleet_id(input)

    if fleet_id in Regents.Keyfleet.Fleets.catalog_ids(),
      do: :ok,
      else: {:error, UnknownFleetError.exception(fleet_id: fleet_id)}
  end

  # A changeset may name the fleet as the record's own field rather than as an argument.
  defp fleet_id(%Ash.Changeset{} = changeset),
    do: Ash.Changeset.get_argument_or_attribute(changeset, :fleet_id)

  defp fleet_id(%input_type{} = input), do: input_type.get_argument(input, :fleet_id)
end
