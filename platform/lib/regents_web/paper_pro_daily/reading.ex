defmodule RegentsWeb.PaperProDaily.Reading do
  @moduledoc "Turns a paper's Markdown answer into the page's HTML: the whole answer, and its opening words."

  @excerpt_words 100
  @extension [table: true, strikethrough: true, math_dollars: true]

  @doc "The answer as HTML, its first hundred words as HTML, and whether there is more to read."
  def render(answer) do
    document = answer |> MDEx.parse_document!(extension: @extension) |> demote_headings()
    {excerpt, _words_left} = excerpt(document.nodes, @excerpt_words)

    %{
      html: html(document),
      excerpt_html: html(%{document | nodes: excerpt}),
      more?: excerpt != document.nodes
    }
  end

  # Each paper's title is a level-two heading, so the answer's headings start at level three.
  defp demote_headings(%MDEx.Heading{} = heading),
    do: %{
      heading
      | level: min(max(heading.level + 1, 3), 6),
        nodes: Enum.map(heading.nodes, &demote_headings/1)
    }

  defp demote_headings(%{nodes: nodes} = node),
    do: %{node | nodes: Enum.map(nodes, &demote_headings/1)}

  defp demote_headings(node), do: node

  # The opening words of the answer, keeping its formatting: everything up to the
  # hundredth word, cut there with an ellipsis. Maths and code count as one word each.
  defp excerpt(nodes, budget) do
    {kept, budget} =
      Enum.reduce_while(nodes, {[], budget}, fn
        _node, {kept, 0} ->
          {:halt, {kept, 0}}

        %MDEx.Text{literal: literal} = text, {kept, budget} ->
          case Regex.scan(~r/\S+/u, literal, return: :index) do
            words when length(words) <= budget ->
              {:cont, {[text | kept], budget - length(words)}}

            words ->
              [{start, length}] = Enum.at(words, budget - 1)
              cut = binary_part(literal, 0, start + length) <> "…"
              {:halt, {[%{text | literal: cut} | kept], 0}}
          end

        %{nodes: children} = node, {kept, budget} ->
          {children, budget} = excerpt(children, budget)
          {:cont, {[%{node | nodes: children} | kept], budget}}

        %{literal: _} = leaf, {kept, budget} ->
          {:cont, {[leaf | kept], budget - 1}}

        node, {kept, budget} ->
          {:cont, {[node | kept], budget}}
      end)

    {Enum.reverse(kept), budget}
  end

  defp html(document), do: MDEx.to_html!(document, extension: @extension, render: [unsafe: false])
end
