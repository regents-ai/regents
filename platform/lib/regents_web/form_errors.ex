defmodule RegentsWeb.FormErrors do
  @moduledoc "The words an Ash form shows under a field once the person has used it."

  import Phoenix.Component, only: [used_input?: 1]

  @spec messages(Phoenix.HTML.FormField.t()) :: [String.t()]
  def messages(field) do
    if used_input?(field), do: Enum.map(field.errors, &message/1), else: []
  end

  # Ash's own words for a missing value, a list too short or text of the wrong
  # length name the rule a value broke; these say what to do about it.
  defp message({"is required", _values}), do: "Fill this in."

  defp message({"must have %{min} or more items", values}),
    do: fill("Add at least %{min}.", values)

  defp message({"length must be less than or equal to %{max}", values}),
    do: fill("Use %{max} characters or fewer.", values)

  defp message({"length must be greater than or equal to %{min}", values}),
    do: fill("Use at least %{min} characters.", values)

  defp message({message, values}), do: fill(message, values)

  # Only the values the words name are filled in: a rule may carry others that
  # are not text, such as the pattern of a `match` validation.
  defp fill(message, values) do
    Regex.replace(~r/%\{(\w+)\}/, message, fn placeholder, key ->
      Enum.find_value(values, placeholder, fn {name, value} ->
        to_string(name) == key && to_string(value)
      end)
    end)
  end
end
