defmodule RegentsWeb.Docs do
  @moduledoc """
  The unified developer documentation's words across every Regents Labs product:
  each page as HTML with its "On this page" headings, as Markdown, and as
  cross-product search data.

  Product documentation is resolved from its live source of truth (static
  committed guides for Regents and Techtree; `RegentsWeb.PublicDocuments.document/1`
  for Cloak, SIWA, Keyfleet, Autolaunch, and Patchbay) so copy and generated tool
  tables never drift.
  """

  import Phoenix.Component, only: [sigil_H: 2]

  alias RegentsWeb.Docs.Pages
  alias RegentsWeb.PublicDocuments

  @max_part_chars 360

  # The page's own element ids, so no heading takes one.
  @shell_ids ~w(docs-article docs-ask-menu docs-copy docs-nav docs-search
                docs-search-index docs-search-input docs-search-results docs-toc-phone
                docs-toc-phone-list docs-toc-spy docs-toc-title)

  # Product doc paths rewritten to stay inside unified `/docs`.
  @doc_link_rewrites [
    {"/techtree/docs/", "/docs/techtree/"},
    {"/techtree/docs", "/docs/techtree"},
    {"/keyfleet/docs", "/docs/keyfleet"},
    {"/autolaunch/docs", "/docs/autolaunch"},
    {"/patchbay/docs", "/docs/patchbay"},
    {"/patchbay/start", "/docs/patchbay/start"},
    {"/patchbay/webmcp", "/docs/patchbay/webmcp"},
    {"/patchbay/agent-setup", "/docs/patchbay/payments"},
    {"/cloak/install", "/docs/cloak/install"}
  ]

  @doc "The page's heading and one-line description."
  def heading(page), do: {page.name, page.description}

  @doc """
  The whole page as Markdown, title and description first: what `Accept:
  text/markdown` and `.md` endpoints answer, and what Copy for LLM copies.
  """
  def markdown(page), do: markdown(page, body(page))

  def markdown(page, body) do
    {name, description} = heading(page)
    "# #{name}\n\n#{description}\n\n" <> body
  end

  @doc """
  The page's body as HTML, with an id on every section heading, a copy icon on
  every code block, LiveView navigation on internal `/docs` links, and the
  headings for "On this page".
  """
  # The HTML is MDEx-sanitized from committed public Markdown; the walk adds
  # only ids, wrappers, internal LiveView link attributes, and the shared copy icon.
  # sobelow_skip ["XSS.Raw"]
  def render(page, body) do
    {nodes, toc} = render_nodes(page, body)
    {nodes |> Floki.raw_html() |> Phoenix.HTML.raw(), toc}
  end

  defp render_nodes(page, body) do
    origin = PublicDocuments.url("")
    ctx = %{origin: origin, page_path: page.path}

    {nodes, {_ids, _blocks, toc}} =
      body
      |> PublicDocuments.html()
      |> Phoenix.HTML.safe_to_string()
      |> Floki.parse_fragment!()
      |> walk({MapSet.new(@shell_ids), 0, []}, ctx)

    {nodes, Enum.reverse(toc)}
  end

  @doc """
  Cross-product search index JSON: each page and each of its sections, tagged
  with product metadata and compact prose excerpts. Cached per origin.
  """
  def search_index do
    origin = PublicDocuments.url("")
    cache_key = {__MODULE__, :search_index_v3, origin}

    case :persistent_term.get(cache_key, nil) do
      nil ->
        index = Jason.encode!(build_search_index())
        :persistent_term.put(cache_key, index)
        index

      index ->
        index
    end
  end

  defp build_search_index do
    for page <- Pages.all() do
      {name, description} = heading(page)
      {nodes, _toc} = render_nodes(page, body(page))

      %{
        path: page.path,
        name: name,
        product: page.product,
        product_name: page.product_name,
        section: page.section,
        description: description,
        parts:
          nodes
          |> Enum.reduce([%{id: nil, title: nil, text: []}], &part/2)
          |> Enum.map(fn entry ->
            text =
              entry.text
              |> Enum.reverse()
              |> Enum.join(" ")
              |> squeeze()
              |> truncate(@max_part_chars)

            %{entry | text: text}
          end)
          |> Enum.reverse()
      }
    end
  end

  # The page cut at each heading: the words under a heading belong to it, and the
  # words before the first heading to the page itself. Skip code blocks so large
  # raw JSON/curl samples do not bloat the client search payload.
  defp part({tag, attrs, children}, parts) when tag in ["h2", "h3"],
    do: [%{id: :proplists.get_value("id", attrs), title: Floki.text(children), text: []} | parts]

  defp part({"div", attrs, children}, parts) do
    if :proplists.get_value("class", attrs) == "docs-code" do
      parts
    else
      append_part_text(parts, Floki.text([{"div", attrs, children}], sep: " "))
    end
  end

  defp part({"pre", _attrs, _children}, parts), do: parts

  defp part(node, parts),
    do: append_part_text(parts, Floki.text([node], sep: " "))

  defp append_part_text([current | rest], ""), do: [current | rest]

  defp append_part_text([current | rest], text),
    do: [%{current | text: [text | current.text]} | rest]

  defp squeeze(text), do: text |> String.split() |> Enum.join(" ")

  defp truncate(text, max) when byte_size(text) <= max, do: text

  defp truncate(text, max) do
    sliced = String.slice(text, 0, max)

    case String.split(sliced, ~r/\s+/) do
      [single] -> single
      words -> words |> Enum.drop(-1) |> Enum.join(" ")
    end
  end

  @doc "Resolves a page’s Markdown body without its title and description."
  def body(page) do
    page.source
    |> resolve_source()
    |> strip_trailer()
    |> strip_h1()
    |> normalize_markdown_links(page)
    |> String.trim()
  end

  defp resolve_source({:file, raw}), do: PublicDocuments.fill(raw)

  defp resolve_source({:doc, doc_path}) do
    case PublicDocuments.document(doc_path) do
      %{markdown: markdown} -> markdown
      _other -> ""
    end
  end

  defp resolve_source({:doc_sections, doc_path, section_ids, opts}) do
    markdown = PublicDocuments.excerpt_source(doc_path) |> strip_trailer()
    {intro, sections} = split_h2_sections(markdown)
    wanted = Enum.map(section_ids, &Map.fetch!(sections, &1))

    parts =
      if Keyword.get(opts, :include_intro, false) do
        intro_clean = intro |> strip_h1() |> String.trim()
        if(intro_clean == "", do: wanted, else: [intro_clean | wanted])
      else
        wanted
      end

    Enum.join(parts, "\n\n")
  end

  # Excerpts use an authored identifier on the line after a heading, so the
  # heading can change without breaking the excerpts. Skip fenced examples.
  defp split_h2_sections(markdown) do
    lines = String.split(markdown, "\n")

    {intro_rev, sections_rev, current_heading, current_lines_rev, _in_fence} =
      Enum.reduce(lines, {[], [], nil, [], false}, fn line,
                                                      {intro, sections, heading, buf, in_fence} ->
        trimmed = String.trim_leading(line)
        toggles_fence? = String.starts_with?(trimmed, "```")
        next_fence = if(toggles_fence?, do: not in_fence, else: in_fence)
        section_id = excerpt_id(in_fence, buf, line)

        cond do
          section_id ->
            {intro, sections, section_id, buf, next_fence}

          not in_fence and not toggles_fence? and String.starts_with?(line, "## ") ->
            next_sections = flush_section(sections, heading, buf)
            new_heading = line |> String.trim_leading("## ") |> String.trim()
            {intro, next_sections, new_heading, [line], next_fence}

          is_nil(heading) ->
            {[line | intro], sections, nil, [], next_fence}

          true ->
            {intro, sections, heading, [line | buf], next_fence}
        end
      end)

    sections = flush_section(sections_rev, current_heading, current_lines_rev)

    intro = intro_rev |> Enum.reverse() |> Enum.join("\n")
    {intro, Map.new(sections)}
  end

  defp excerpt_id(false, [_heading], "<!-- docs-section: " <> rest),
    do: String.trim_trailing(rest, " -->")

  defp excerpt_id(_in_fence, _lines, _line), do: nil

  defp flush_section(sections, nil, _buf), do: sections

  defp flush_section(sections, heading, buf) do
    text = buf |> Enum.reverse() |> Enum.join("\n") |> String.trim()
    [{heading, text} | sections]
  end

  defp strip_trailer(markdown) do
    String.replace(
      markdown,
      ~r/\n---\n\n(?:Every Techtree page|Patchbay) answers .*?\z/s,
      ""
    )
  end

  # Remove top-level `# H1` lines outside code fences since `DocsLive` renders
  # the single canonical `<h1>` above `.docs-prose`.
  defp strip_h1(markdown) do
    {lines_rev, _in_fence} =
      markdown
      |> String.split("\n")
      |> Enum.reduce({[], false}, fn line, {acc, in_fence} ->
        trimmed = String.trim_leading(line)
        toggles_fence? = String.starts_with?(trimmed, "```")
        next_fence = if(toggles_fence?, do: not in_fence, else: in_fence)

        if not in_fence and not toggles_fence? and String.starts_with?(line, "# ") do
          {acc, next_fence}
        else
          {[line | acc], next_fence}
        end
      end)

    lines_rev
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # Rewrite markdown links outside code fences so product doc links stay inside
  # `/docs/...` and relative/fragment links pass MDEx's strict `url_relative: :deny`
  # check before `walk/3` converts internal URLs back to clean relative paths.
  defp normalize_markdown_links(markdown, page) do
    origin = PublicDocuments.url("")

    {lines_rev, _in_fence} =
      markdown
      |> String.split("\n")
      |> Enum.reduce({[], false}, fn line, {acc, in_fence} ->
        trimmed = String.trim_leading(line)
        toggles_fence? = String.starts_with?(trimmed, "```")
        next_fence = if(toggles_fence?, do: not in_fence, else: in_fence)

        updated =
          if in_fence or toggles_fence? do
            line
          else
            rewrite_line_links(line, origin, page.path)
          end

        {[updated | acc], next_fence}
      end)

    lines_rev |> Enum.reverse() |> Enum.join("\n")
  end

  defp rewrite_line_links(line, origin, page_path) do
    Regex.replace(~r/\]\(([^)\s]+)\)/, line, fn _whole, target ->
      "](" <> normalize_link_target(target, origin, page_path) <> ")"
    end)
  end

  defp normalize_link_target("#" <> _rest = fragment, origin, page_path),
    do: origin <> page_path <> fragment

  defp normalize_link_target("/" <> _rest = rel_path, origin, _page_path),
    do: origin <> rewrite_doc_path(rel_path)

  defp normalize_link_target(url, origin, _page_path) do
    if String.starts_with?(url, origin <> "/") do
      rel = String.replace_prefix(url, origin, "")
      origin <> rewrite_doc_path(rel)
    else
      url
    end
  end

  defp rewrite_doc_path(path) do
    {base, fragment} =
      case String.split(path, "#", parts: 2) do
        [only] -> {only, ""}
        [left, right] -> {left, "#" <> right}
      end

    rewritten =
      Enum.reduce_while(@doc_link_rewrites, base, fn {from, to}, current ->
        cond do
          String.ends_with?(from, "/") and String.starts_with?(current, from) ->
            {:halt, String.replace_prefix(current, from, to)}

          current == from ->
            {:halt, to}

          true ->
            {:cont, current}
        end
      end)

    rewritten <> fragment
  end

  defp walk(nodes, state, ctx) do
    Enum.flat_map_reduce(nodes, state, fn
      {tag, attrs, children}, {ids, blocks, toc} when tag in ["h2", "h3"] ->
        title = Floki.text(children)
        id = unique_id(slug(title), ids)
        level = if tag == "h2", do: 2, else: 3

        {[{tag, [{"id", id} | attrs], children}],
         {MapSet.put(ids, id), blocks, [%{id: id, title: title, level: level} | toc]}}

      {"a", attrs, children}, state ->
        {children, state} = walk(children, state, ctx)
        {[{"a", rewrite_anchor_attrs(attrs, ctx), children}], state}

      {"pre", attrs, children}, {ids, blocks, toc} ->
        id = "docs-code-#{blocks + 1}"
        code = {"pre", [{"id", id}, {"tabindex", "0"} | attrs], children}
        {[{"div", [{"class", "docs-code"}], [code | copy_icon(id)]}], {ids, blocks + 1, toc}}

      {"table", attrs, children}, state ->
        {children, state} = walk(children, state, ctx)

        {[
           {"div",
            [
              {"class", "docs-table"},
              {"tabindex", "0"},
              {"role", "region"},
              {"aria-label", "Table"}
            ], [card_table(attrs, children)]}
         ], state}

      {tag, attrs, children}, state ->
        {children, state} = walk(children, state, ctx)
        {[{tag, attrs, children}], state}

      node, state ->
        {[node], state}
    end)
  end

  defp rewrite_anchor_attrs(attrs, %{origin: origin, page_path: page_path}) do
    same_page_prefix = origin <> page_path <> "#"

    case :proplists.get_value("href", attrs, nil) do
      href when is_binary(href) ->
        cond do
          String.starts_with?(href, same_page_prefix) ->
            frag = "#" <> String.replace_prefix(href, same_page_prefix, "")
            replace_href(attrs, frag, drop_rel: true, live_link: false)

          String.starts_with?(href, origin <> "/docs") and not String.ends_with?(href, ".md") ->
            rel = String.replace_prefix(href, origin, "")
            replace_href(attrs, rel, drop_rel: true, live_link: true)

          String.starts_with?(href, origin <> "/") ->
            rel = String.replace_prefix(href, origin, "")
            replace_href(attrs, rel, drop_rel: true, live_link: false)

          true ->
            attrs
        end

      _other ->
        attrs
    end
  end

  defp replace_href(attrs, new_href, opts) do
    drop_rel? = Keyword.get(opts, :drop_rel, false)
    live_link? = Keyword.get(opts, :live_link, false)

    cleaned =
      Enum.flat_map(attrs, fn
        {"href", _} -> [{"href", new_href}]
        {"rel", _} when drop_rel? -> []
        other -> [other]
      end)

    if live_link? do
      cleaned ++ [{"data-phx-link", "redirect"}, {"data-phx-link-state", "push"}]
    else
      cleaned
    end
  end

  # Under 768px a table stands as one card a row (docs.css), so it states its
  # table roles itself and each cell names its column.
  defp card_table(attrs, children) do
    columns =
      children
      |> Floki.find("thead th")
      |> Enum.map(&(&1 |> Floki.text() |> squeeze()))

    {"table", [{"role", "table"} | attrs], Enum.map(children, &card_part(&1, columns))}
  end

  defp card_part({tag, attrs, rows}, columns) when tag in ["thead", "tbody"],
    do: {tag, [{"role", "rowgroup"} | attrs], Enum.map(rows, &card_row(&1, columns))}

  defp card_part(node, _columns), do: node

  defp card_row({"tr", attrs, cells}, columns) do
    cells =
      cells
      |> Enum.filter(&match?({_tag, _attrs, _children}, &1))
      |> Enum.with_index()
      |> Enum.map(fn
        {{"th", attrs, children}, _index} ->
          {"th", [{"role", "columnheader"} | attrs], children}

        {{"td", attrs, children}, index} ->
          {"td", [{"role", "cell"}, {"data-label", Enum.at(columns, index, "")} | attrs],
           children}
      end)

    {"tr", [{"role", "row"} | attrs], cells}
  end

  defp card_row(node, _columns), do: node

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
