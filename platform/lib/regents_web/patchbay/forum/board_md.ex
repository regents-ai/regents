defmodule RegentsWeb.Patchbay.Forum.BoardMD do
  @moduledoc """
  Patchbay's agent pages as markdown: the same facts as the page, for a reader
  that asked for `text/markdown`. So far agent setup, payments and the
  troubleshooting pages.
  """

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD
  import RegentsWeb.Patchbay.Forum.BoardHTML, only: [start_profiles: 0, start_steps: 0]

  embed_markdown("board_md/*")

  @doc "What to do in one agent page step: sentences, and commands as code blocks."
  def step_lines(items), do: Enum.map_join(items, "\n\n", &step_line/1)

  defp step_line({:say, parts}), do: sentence(parts)
  defp step_line({:run, text}), do: block(text)

  @doc "One sentence of an agent page or a troubleshooting page, from its parts."
  def sentence(parts), do: Enum.map_join(parts, &step_part/1)

  defp step_part({:c, text}), do: "`" <> text <> "`"
  defp step_part({:a, label, href}), do: "[#{label}](#{href})"
  defp step_part(text), do: text
end
