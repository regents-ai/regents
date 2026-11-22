defmodule RegentsWeb.Keyfleet.Diff do
  @moduledoc """
  The lines of one file's change as a commit page shows them, from git's
  patch of it (its hunks, from the first `@@`): each `%{kind:, old:, new:,
  text:}`, `kind` `:hunk` for where a run of changes starts, `:added`,
  `:removed` or `:same`, and `old` and `new` the line's number before and
  after, nil on the side it isn't on.
  """

  @hunk ~r/\A@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@ ?(.*)\z/

  def lines(patch) do
    patch
    |> String.split("\n")
    |> drop_last_empty()
    |> Enum.map_reduce({0, 0}, &line/2)
    |> elem(0)
    |> Enum.reject(&is_nil/1)
  end

  defp drop_last_empty(lines) do
    if List.last(lines) == "", do: List.delete_at(lines, -1), else: lines
  end

  defp line("@@" <> _rest = header, at) do
    case Regex.run(@hunk, header) do
      [_header, old, new, context] ->
        {%{kind: :hunk, old: nil, new: nil, text: context},
         {String.to_integer(old), String.to_integer(new)}}

      nil ->
        {nil, at}
    end
  end

  defp line("+" <> text, {old, new}),
    do: {%{kind: :added, old: nil, new: new, text: text}, {old, new + 1}}

  defp line("-" <> text, {old, new}),
    do: {%{kind: :removed, old: old, new: nil, text: text}, {old + 1, new}}

  defp line(" " <> text, {old, new}),
    do: {%{kind: :same, old: old, new: new, text: text}, {old + 1, new + 1}}

  # "\ No newline at end of file", and anything else git notes between lines.
  defp line(_note, at), do: {nil, at}
end
