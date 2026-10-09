defmodule RegentsWeb.PaperProDaily.Reading do
  @moduledoc "Turns a paper's Markdown answer into the page's HTML: the whole answer, and its opening words."

  @excerpt_words 100
  @extension [table: true, strikethrough: true, math_dollars: true]

  @doc "A paper's details and complete, original analysis as Markdown."
  def details_markdown(paper) do
    """
    ## #{paper.title}

    Date: #{Calendar.strftime(paper.date, "%m-%d-%Y")}
    Paper URL: #{paper.arxiv_url}
    ChatGPT URL: #{paper.chatgpt_url}
    ChatGPT model: #{paper.author}

    """ <> paper.answer
  end

  @doc "All papers as Markdown, including those not yet reached by scrolling."
  def page_markdown(papers) do
    "# Paper Pro Daily\n\nA research paper each day, read with ChatGPT Astra 6 Pro.\n\n" <>
      Enum.map_join(papers, "\n\n---\n\n", &details_markdown/1)
  end

  @doc "The opening paper information, analysis HTML, excerpt, and whether there is more to read."
  def render(answer) do
    document = answer |> MDEx.parse_document!(extension: @extension) |> demote_headings()
    {opening, analysis} = split_opening(document.nodes)
    document = %{document | nodes: analysis}
    {excerpt, _words_left} = excerpt(document.nodes, @excerpt_words)

    %{
      opening_html: html(%{document | nodes: opening}),
      html: html(document),
      excerpt_html: html(%{document | nodes: excerpt}),
      more?: excerpt != document.nodes
    }
  end

  # Reviews open with a heading and optional citation paragraph. An assessment
  # belongs below the model credit, even when it shares the citation's paragraph.
  defp split_opening(nodes) do
    {headings, rest} = Enum.split_while(nodes, &match?(%MDEx.Heading{}, &1))

    case rest do
      [%MDEx.Paragraph{nodes: inline} = paragraph | tail] ->
        {citation, assessment} = Enum.split_while(inline, &(not assessment?(&1)))

        if assessment != [] or assessment_follows?(tail) or match?([%MDEx.Emph{} | _], inline) do
          opening =
            if citation == [], do: headings, else: headings ++ [%{paragraph | nodes: citation}]

          analysis =
            if assessment == [], do: tail, else: [%{paragraph | nodes: assessment} | tail]

          {opening, analysis}
        else
          {headings, rest}
        end

      _ ->
        {headings, rest}
    end
  end

  defp assessment?(%MDEx.Strong{nodes: [%MDEx.Text{literal: text} | _]}),
    do: String.starts_with?(text, ["My assessment", "Overall assessment", "My verdict"])

  defp assessment?(_), do: false

  defp assessment_follows?([%MDEx.Paragraph{nodes: [first | _]} | _]), do: assessment?(first)
  defp assessment_follows?(_), do: false

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
