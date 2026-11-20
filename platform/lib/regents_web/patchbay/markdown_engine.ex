defmodule RegentsWeb.Patchbay.MarkdownEngine do
  @moduledoc """
  Compiles Patchbay's `.md.eex` templates: plain EEx, so nothing is HTML-escaped
  and a value on its own line keeps the blank lines around it that make it a
  paragraph, with the rendered document tidied so that a loop or a condition
  written on its own line leaves no blank line behind it to split a list or a
  table.

  The site names no engine for `.eex` files, so a module takes its Markdown
  templates with `embed_markdown/1` rather than `embed_templates/1`.
  """

  @behaviour Phoenix.Template.Engine

  @doc """
  One function per `.md.eex` file matching `pattern` beside the calling module,
  named after the file, compiled by this engine.
  """
  defmacro embed_markdown(pattern) do
    quote bind_quoted: [pattern: pattern] do
      require Phoenix.Template

      Phoenix.Template.compile_all(
        &Path.basename(&1, ".md.eex"),
        __DIR__,
        pattern,
        %{eex: RegentsWeb.Patchbay.MarkdownEngine}
      )
    end
  end

  @impl Phoenix.Template.Engine
  def compile(path, _name) do
    rendered = EEx.compile_file(path, engine: EEx.SmartEngine, trim: false, line: 1)

    quote do
      RegentsWeb.Patchbay.MarkdownEngine.tidy(unquote(rendered))
    end
  end

  @doc """
  Markdown with no more than one blank line in a row, no blank line between
  two rows of one table or two items of one list, and one newline at the end.
  """
  @spec tidy(iodata()) :: String.t()
  def tidy(rendered) do
    rendered
    |> IO.iodata_to_binary()
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/(\|[^\n]*\|)\n\n(?=\|)/, "\\1\n")
    |> String.replace(~r/^( *(?:[-*]|\d+\.) [^\n]*)\n\n(?= *(?:[-*]|\d+\.) )/m, "\\1\n")
    |> String.trim()
    |> Kernel.<>("\n")
  end
end
