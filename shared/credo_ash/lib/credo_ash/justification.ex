defmodule CredoAsh.Justification do
  @moduledoc """
  Shared handling for escape hatches that are allowed when they are explained.

  Some findings are not defects on their own — going around Ash, or turning
  policies off, is occasionally the right answer. What makes them safe is a
  reader being able to tell a deliberate choice from an accident, so a comment
  next to the line clears the finding.
  """

  @doc """
  Whether the given line has been explained by a comment.

  The unit is the enclosing function, not the single line. People document a
  cleanup block once and then write five deletes under it, and demanding a
  repeated comment above each one would produce noise rather than clarity. So a
  comment anywhere inside the enclosing `def`/`defp` — or in the comment block
  directly above its head — clears every finding in that function. The trade is
  deliberate: an unrelated comment in the same function will also clear them.
  """
  @spec justified?(Credo.SourceFile.t(), pos_integer()) :: boolean()
  def justified?(source_file, line_no) do
    lines = Credo.SourceFile.lines(source_file)
    comments = comments(source_file)
    explanations = Enum.reject(comments, &empty_comment?/1)

    case Enum.find(lines, fn {no, _line} -> no == line_no end) do
      nil ->
        false

      {_no, line} ->
        trailing_comment?(explanations, line_no, line) or
          explained_above?(line_no, lines, comments, explanations)
    end
  end

  defp explained_above?(line_no, lines, comments, explanations) do
    start_line = scope_start(line_no, lines, comments)

    Enum.any?(explanations, fn %{line: comment_line} ->
      comment_line >= start_line and comment_line < line_no
    end)
  end

  # The first line of the region a comment can speak for: the enclosing function
  # head, extended up through any comment block sitting directly on top of it.
  defp scope_start(line_no, lines, comments) do
    head =
      lines
      |> Enum.take(line_no - 1)
      |> Enum.reverse()
      |> Enum.find(fn {_no, line} -> function_head?(line) end)

    case head do
      nil -> 1
      {no, _line} -> climb_comments(no, comment_only_lines(lines, comments))
    end
  end

  defp comment_only_lines(lines, comments) do
    lines_by_number = Map.new(lines)

    comments
    |> Enum.filter(fn
      %{line: line_no, column: column} ->
        code_before_comment =
          lines_by_number
          |> Map.get(line_no, "")
          |> String.slice(0, column - 1)

        String.trim(code_before_comment) == ""

      _comment ->
        false
    end)
    |> MapSet.new(& &1.line)
  end

  defp climb_comments(no, comment_lines) when no > 1 do
    if MapSet.member?(comment_lines, no - 1) do
      climb_comments(no - 1, comment_lines)
    else
      no
    end
  end

  defp climb_comments(no, _comment_lines), do: no

  defp function_head?(line), do: Regex.match?(~r/^\s*defp?\s/, line)

  # A bare `#` explains nothing, so it never justifies a finding; it still
  # belongs to the comment block above a function head when climbing.
  defp empty_comment?(%{text: text}), do: String.trim(text, "#") |> String.trim() == ""

  # Comments come from the tokenizer, so a `#` inside a string, sigil or heredoc
  # is never mistaken for one.
  defp comments(source_file) do
    case source_file
         |> Credo.SourceFile.source()
         |> Code.string_to_quoted_with_comments(columns: true) do
      {:ok, _ast, comments} -> comments
      {:error, _error} -> []
    end
  end

  defp trailing_comment?(comments, line_no, line) do
    Enum.any?(comments, fn
      %{line: ^line_no, column: column} ->
        code_before_comment = String.slice(line, 0, column - 1)
        String.trim(code_before_comment) != ""

      _comment ->
        false
    end)
  end
end
