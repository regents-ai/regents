defmodule Regents.Keyfleet.Graph.Validations.FreshOwnership do
  @moduledoc """
  The fleet's key ownership is fresh enough to act on, so a write refused for
  want of it says so rather than calling its author a stranger.
  """
  use Ash.Resource.Validation

  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError

  @impl true
  def supports(_opts), do: [Ash.ActionInput]

  @impl true
  def validate(input, _opts, _context) do
    fleet_id = Ash.ActionInput.get_argument(input, :fleet_id)

    if Regents.Keyfleet.Chain.fresh?(fleet_id),
      do: :ok,
      else: {:error, OwnershipRefreshingError.exception(fleet_id: fleet_id)}
  end
end
