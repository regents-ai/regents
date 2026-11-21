defmodule Regents.Keyfleet.Projects.Validations.NotGeneral do
  @moduledoc """
  The step names a project other than `general`, which is never deleted, by
  any Key and in any state: it keeps the fleet's starting goals, its first
  notebook space and its first repository.
  """
  use Ash.Resource.Validation

  alias Regents.Keyfleet.Projects.Errors.HoldError

  @impl true
  def supports(_opts), do: [Ash.ActionInput]

  @impl true
  def validate(input, _opts, _context) do
    general = Regents.Keyfleet.Projects.general()

    if Ash.ActionInput.get_argument(input, :name) == general,
      do:
        {:error,
         HoldError.exception(
           code: :general_kept,
           words: "General can't be deleted.",
           project: general
         )},
      else: :ok
  end
end
