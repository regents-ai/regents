defmodule RegentsWeb.Docs do
  @moduledoc """
  The developer documentation's words: each page as HTML with its "On this
  page" headings, as Markdown, and as search data. A page's title and one-line
  description come from `RegentsWeb.PublicDocuments`, so the page, its
  Markdown, search results and the browser tab all say the same thing.
  """

  import Phoenix.Component, only: [sigil_H: 2]

  alias RegentsWeb.Docs.Pages
  alias RegentsWeb.PublicDocuments

  # The page's own element ids, so no heading takes one.
  @shell_ids ~w(docs-article docs-ask-menu docs-copy docs-nav docs-search-index
                docs-search-input docs-search-results docs-toc-title)

  @doc "The page's title and description, as the browser tab and search results show them."
  def heading(page) do
    [page_title: _, page_description: description] = PublicDocuments.page(page.path)
    {page.name, description}
  end

  @doc """
  The whole page as Markdown, title and description first: what `Accept:
  text/markdown` answers at the page's own address, and what Copy for LLM copies.
  """
  def markdown(page) do
    {name, description} = heading(page)
    "# #{name}\n\n#{description}\n\n" <> body(page)
  end

  @doc """
  The page's body as HTML, with an id on every section heading and a copy icon on
  every code block, and the headings for "On this page".
  """
  # The HTML is MDEx-sanitized from the committed docs Markdown; the walk adds
  # only ids, wrappers and the shared copy icon.
  # sobelow_skip ["XSS.Raw"]
  def render(page) do
    {nodes, {_ids, _blocks, toc}} =
      page
      |> body()
      |> PublicDocuments.html()
      |> Phoenix.HTML.safe_to_string()
      |> Floki.parse_fragment!()
      |> walk({MapSet.new(@shell_ids), 0, []})

    {nodes |> Floki.raw_html() |> Phoenix.HTML.raw(), Enum.reverse(toc)}
  end

  @doc """
  What the search box looks through, as JSON: each page and each of its
  sections, with the words in it. Built once from the same Markdown the pages
  show, and escaped so no text in it can close the script tag that holds it.
  """
  def search_index do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        index = Jason.encode!(build_search_index(), escape: :html_safe)
        :persistent_term.put(__MODULE__, index)
        index

      index ->
        index
    end
  end

  defp build_search_index do
    for page <- Pages.all() do
      {name, description} = heading(page)
      {html, _toc} = render(page)

      %{
        path: page.path,
        name: name,
        section: page.section,
        description: description,
        parts:
          html
          |> Phoenix.HTML.safe_to_string()
          |> Floki.parse_fragment!()
          |> Enum.reduce([%{id: nil, title: nil, text: []}], &part/2)
          |> Enum.map(&%{&1 | text: &1.text |> Enum.reverse() |> Enum.join(" ") |> squeeze()})
          |> Enum.reverse()
      }
    end
  end

  # The page cut at each heading: the words under a heading belong to it, and the
  # words before the first heading to the page itself.
  defp part({tag, attrs, children}, parts) when tag in ["h2", "h3"],
    do: [%{id: :proplists.get_value("id", attrs), title: Floki.text(children), text: []} | parts]

  defp part(node, [current | parts]),
    do: [%{current | text: [Floki.text([node], sep: " ") | current.text]} | parts]

  defp squeeze(text), do: text |> String.split() |> Enum.join(" ")

  defp body(page), do: PublicDocuments.fill(page.source)

  defp walk(nodes, state) do
    Enum.flat_map_reduce(nodes, state, fn
      {tag, attrs, children}, {ids, blocks, toc} when tag in ["h2", "h3"] ->
        title = Floki.text(children)
        id = unique_id(slug(title), ids)
        level = if tag == "h2", do: 2, else: 3

        {[{tag, [{"id", id} | attrs], children}],
         {MapSet.put(ids, id), blocks, [%{id: id, title: title, level: level} | toc]}}

      {"pre", attrs, children}, {ids, blocks, toc} ->
        id = "docs-code-#{blocks + 1}"
        code = {"pre", [{"id", id}, {"tabindex", "0"} | attrs], children}
        {[{"div", [{"class", "docs-code"}], [code | copy_icon(id)]}], {ids, blocks + 1, toc}}

      {"table", attrs, children}, state ->
        {[
           {"div",
            [
              {"class", "docs-table"},
              {"tabindex", "0"},
              {"role", "region"},
              {"aria-label", "Table"}
            ], [{"table", attrs, children}]}
         ], state}

      {tag, attrs, children}, state ->
        {children, state} = walk(children, state)
        {[{tag, attrs, children}], state}

      node, state ->
        {[node], state}
    end)
  end

  defp slug(title) do
    case title
         |> String.downcase()
         |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
         |> String.trim("-") do
      "" -> "section"
      slug -> slug
    end
  end

  defp unique_id(base, ids) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&if(&1 == 1, do: base, else: "#{base}-#{&1}"))
    |> Enum.find(&(not MapSet.member?(ids, &1)))
  end

  # The shared copy icon, drawn by its own component so the page-wide copy
  # listener answers it like every other.
  defp copy_icon(target) do
    assigns = %{target: target}

    ~H"""
    <Regent.Primitives.copy_icon id={@target <> "-copy"} target={@target} label="Copy code" />
    """
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> Floki.parse_fragment!()
  end
end
