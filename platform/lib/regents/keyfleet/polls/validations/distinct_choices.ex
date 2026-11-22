defmodule Regents.Keyfleet.Polls.Validations.DistinctChoices do
  @moduledoc "No two of a poll's choices are the same, so a vote names exactly one."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    choices = Ash.Changeset.get_attribute(changeset, :choices) || []

    if length(Enum.uniq(choices)) == length(choices),
      do: :ok,
      else: {:error, field: :choices, message: "must each be different"}
  end
end
