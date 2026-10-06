defmodule RegentsWeb.FormErrors do
  @moduledoc "The words an Ash form shows under a field once the person has used it."

  import Phoenix.Component, only: [used_input?: 1]

  @spec messages(Phoenix.HTML.FormField.t()) :: [String.t()]
  def messages(field) do
    if used_input?(field), do: Enum.map(field.errors, &message/1), else: []
  end

  defp message({message, values}) do
    Enum.reduce(values, message, fn {key, value}, message ->
      String.replace(message, "%{#{key}}", to_string(value))
    end)
  end
end
