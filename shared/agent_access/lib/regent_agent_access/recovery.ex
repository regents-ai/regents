defmodule RegentAgentAccess.Recovery do
  @moduledoc """
  Error bodies that tell a reader where to go next, without request, session or
  exception details. The product supplies the status title and its own links.
  """

  @doc "A Markdown error page: the status `title` and `links` as `{label, url}` pairs."
  @spec markdown(String.t(), [{String.t(), String.t()}]) :: String.t()
  def markdown(title, links) do
    "# #{title}\n\nThis request could not be completed. Use these public entry points to continue:\n\n" <>
      Enum.map_join(links, "\n", fn {label, url} -> "- [#{label}](#{url})" end) <> "\n"
  end

  @doc """
  A JSON error body, `%{error: %{code, message, hint}}`: the status `message`, a
  code derived from it, and the product's `hint` saying what to do next.
  """
  @spec json(String.t(), String.t()) :: map()
  def json(message, hint) do
    %{
      error: %{
        code: message |> String.downcase() |> String.replace(" ", "_"),
        message: message,
        hint: hint
      }
    }
  end
end
