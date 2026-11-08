defmodule RegentsWeb.PaperProDaily.Reading do
  @moduledoc "Turns a paper's Markdown answer into the page's HTML: the whole answer, and its opening words."

  @excerpt_words 100
  @extension [table: true, strikethrough: true, math_dollars: true, inline_code_attributes: false]

  @doc "The short name that ends a paper's address."
  def anchor(paper), do: String.slice(paper.id, 0, 8)

  @doc "The full address that opens this paper on its page."
  def url(paper), do: RegentsWeb.PublicDocuments.url("/paper-pro-daily/#{anchor(paper)}")

  @doc "A paper's authors for a shared link: all of up to three, or the first three."
  def byline(%{authors: [first, second, third, _fourth | _rest]}),
    do: Enum.join([first, second, third], ", ") <> " et al."

  def byline(%{authors: authors}), do: Enum.join(authors, ", ")

  @doc "A paper's details and complete, original analysis as Markdown."
  def details_markdown(paper) do
    """
    ## #{paper.title}

    Date: #{Calendar.strftime(paper.date, "%m-%d-%Y")}
    Paper URL: #{paper.arxiv_url}
    ChatGPT URL: #{paper.chatgpt_url}
    ChatGPT model: #{paper.author}
    Tags: #{Enum.join(paper.tags, ", ")}

    """ <> paper.answer
  end

  @doc "All papers as Markdown, including those not yet reached by scrolling."
  def page_markdown(papers) do
    "# Paper Pro Daily\n\nA research paper each day, read with ChatGPT Astra 6 Pro.\n\n" <>
      papers_markdown(papers)
  end

  @doc "The papers filed under any of the chosen tags, as Markdown."
  def filtered_markdown(papers, tags) do
    "# Paper Pro Daily: #{Enum.join(tags, ", ")}\n\n" <> papers_markdown(papers)
  end

  defp papers_markdown(papers), do: Enum.map_join(papers, "\n\n---\n\n", &details_markdown/1)

  @doc "The tags an address names (`?tags=A,B`), in the page's order; unknown names are left out."
  def chosen_tags(%{"tags" => tags}) when is_binary(tags) do
    names = String.split(tags, ",")
    Enum.filter(Regents.PaperProDaily.Tag.values(), &(&1 in names))
  end

  def chosen_tags(_params), do: []

  @doc "The address query that keeps the chosen tags, or nothing when none is chosen."
  def tags_query([]), do: ""
  def tags_query(tags), do: "?" <> URI.encode_query(tags: Enum.join(tags, ","))

  @doc "The papers filed under any of the chosen tags; all of them when none is chosen."
  def filed_under(papers, []), do: papers

  def filed_under(papers, tags),
    do: Enum.filter(papers, &Enum.any?(&1.tags, fn tag -> tag in tags end))

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
          {headings ++ part(paragraph, citation), part(paragraph, assessment) ++ tail}
        else
          {headings, rest}
        end

      _ ->
        {headings, rest}
    end
  end

  defp part(_paragraph, []), do: []
  defp part(paragraph, inline), do: [%{paragraph | nodes: inline}]

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

  defp html(document) do
    document
    |> MDEx.to_html!(extension: @extension, render: [unsafe: false])
    |> Floki.parse_fragment!()
    |> Floki.traverse_and_update(fn
      {"table", attrs, children} ->
        {"div",
         [
           {"class", "rg-blog-table"},
           {"tabindex", "0"},
           {"role", "region"},
           {"aria-label", "Scrollable table"}
         ], [{"table", attrs, children}]}

      node ->
        node
    end)
    |> Floki.raw_html()
  end
end
