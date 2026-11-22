defmodule Regents.Keyfleet.Graph.Validations.DistinctIds do
  @moduledoc "The request names each object once (its `ids`), so every one it names is answered."
  use Ash.Resource.Validation

  @impl true
  def supports(_opts), do: [Ash.ActionInput]

  @impl true
  def validate(input, _opts, _context) do
    ids = Ash.ActionInput.get_argument(input, :ids) || []

    if length(Enum.uniq(ids)) == length(ids),
      do: :ok,
      else: {:error, field: :ids, message: "must name each object once"}
  end
end
