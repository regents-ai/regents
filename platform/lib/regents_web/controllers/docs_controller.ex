defmodule RegentsWeb.DocsController do
  @moduledoc "The developer documentation pages; no account or database reads."
  use RegentsWeb, :controller
  alias RegentsWeb.{Docs, Docs.Pages, PublicDocuments}

  def show(conn, _params) do
    page = Pages.page(conn.private.docs_path)
    {html, toc} = Docs.render(page)
    {name, description} = Docs.heading(page)
    {previous, next} = Pages.neighbours(page)
    sections = Pages.sections()
    {_, [first | _]} = List.keyfind(sections, page.section, 0)
    ask = "Read #{PublicDocuments.url(page.path)} so you can answer questions about it."

    render(
      conn,
      :show,
      [
        page: page,
        html: html,
        toc: toc,
        markdown: Docs.markdown(page),
        name: name,
        description: description,
        previous: previous,
        next: next,
        sections: sections,
        section_path: first.path,
        claude: "https://claude.ai/new?" <> URI.encode_query(q: ask),
        chatgpt: "https://chatgpt.com/?" <> URI.encode_query(q: ask)
      ] ++ PublicDocuments.page(page.path)
    )
  end
end

defmodule RegentsWeb.DocsHTML do
  @moduledoc false
  use RegentsWeb, :html

  alias RegentsWeb.Docs

  def show(assigns) do
    ~H"""
    <div class="docs rg-sheet rg-frame" data-docs>
      <a class="docs-skip" href="#docs-article">Skip to content</a>
      <header class="docs-top">
        <a class="docs-brand" href={~p"/"} aria-label="Regents Labs home">
          <span class="docs-brand__mark" aria-hidden="true">
            <img class="docs-brand__light" src="/images/brand/regents-crown-flat-light.svg" alt="" />
            <img class="docs-brand__dark" src="/images/brand/regents-crown-flat-dark.svg" alt="" />
          </span>
          <span class="docs-brand__name">Regents Labs</span>
        </a>
        <a class="docs-brand__docs" href={~p"/docs"}>Docs</a>

        <div class="docs-search" role="search">
          <label class="visually-hidden" for="docs-search-input">Search</label>
          <input
            id="docs-search-input"
            type="search"
            placeholder="Search"
            autocomplete="off"
            spellcheck="false"
            role="combobox"
            aria-expanded="false"
            aria-controls="docs-search-results"
            aria-autocomplete="list"
          />
          <kbd class="docs-search__key" aria-hidden="true">/</kbd>
          <ul
            id="docs-search-results"
            class="docs-search__results"
            role="listbox"
            aria-label="Results"
            hidden
          >
          </ul>
        </div>

        <span class="docs-ask">
          <Regent.Primitives.button variant="secondary" arrow={false} popovertarget="docs-ask-menu">
            Ask AI
          </Regent.Primitives.button>
          <div id="docs-ask-menu" class="docs-menu" popover>
            <a href={@claude} target="_blank" rel="noopener noreferrer">Claude</a>
            <a href={@chatgpt} target="_blank" rel="noopener noreferrer">ChatGPT</a>
          </div>
        </span>

        <Regent.Primitives.button
          variant="quiet"
          arrow={false}
          class="docs-menu-button"
          popovertarget="docs-nav"
        >
          Menu
        </Regent.Primitives.button>
      </header>

      <nav class="docs-tabs" aria-label="Sections">
        <a
          :for={{section, [first | _]} <- @sections}
          href={first.path}
          aria-current={if(section == @page.section, do: "true")}
        >
          {section}
        </a>
      </nav>

      <div class="docs-body">
        <nav id="docs-nav" class="docs-nav" aria-label="Docs" popover>
          <Regent.Primitives.button
            variant="quiet"
            arrow={false}
            class="docs-nav__close"
            popovertarget="docs-nav"
            popovertargetaction="hide"
          >
            Close
          </Regent.Primitives.button>
          <details
            :for={{section, pages} <- @sections}
            class="docs-nav__group"
            open={section == @page.section}
          >
            <summary>{section}</summary>
            <ul>
              <li :for={page <- pages}>
                <a href={page.path} aria-current={if(page.path == @page.path, do: "page")}>
                  {page.name}
                </a>
              </li>
            </ul>
          </details>
          <div class="docs-nav__foot">
            <a href={~p"/llms.txt"}>llms.txt</a>
            <a href={~p"/openapi.json"}>OpenAPI</a>
            <a href={~p"/about"}>About</a>
          </div>
        </nav>

        <main id="docs-article" class="docs-article" tabindex="-1">
          <nav class="docs-crumbs" aria-label="Breadcrumb">
            <ol>
              <li><a href={~p"/docs"}>Docs</a></li>
              <li :if={@page.path != "/docs"}><a href={@section_path}>{@page.section}</a></li>
              <li><span aria-current="page">{@name}</span></li>
            </ol>
          </nav>
          <h1 class="docs-title">{@name}</h1>
          <p class="docs-lede">{@description}</p>

          <div class="docs-actions">
            <Regent.Primitives.copy_button id="docs-copy" text={@markdown} variant="quiet">
              Copy for LLM
            </Regent.Primitives.copy_button>
            <Regent.Primitives.button variant="quiet" arrow={false} data-docs-markdown>
              View as Markdown
            </Regent.Primitives.button>
            <a href={~p"/start"} class="rg-button rg-button--primary">
              <span class="rg-button__label">Set up agent</span>
            </a>
          </div>

          <details :if={@toc != []} class="docs-toc-phone">
            <summary>On this page</summary>
            <.toc toc={@toc} />
          </details>

          <div class="docs-prose">{@html}</div>

          <nav class="docs-pager" aria-label="More docs">
            <a :if={@previous} class="docs-pager__previous" href={@previous.path}>
              <span>Previous</span>
              {@previous.name}
            </a>
            <a :if={@next} class="docs-pager__next" href={@next.path}>
              <span>Next</span>
              {@next.name}
            </a>
          </nav>
        </main>

        <aside :if={@toc != []} class="docs-toc" aria-labelledby="docs-toc-title">
          <p id="docs-toc-title" class="docs-toc__title">On this page</p>
          <.toc toc={@toc} spy />
        </aside>
      </div>

      <script type="application/json" id="docs-search-index">
        <%= search_index() %>
      </script>
    </div>
    """
  end

  attr :toc, :list, required: true
  attr :spy, :boolean, default: false

  defp toc(assigns) do
    ~H"""
    <ul class="docs-toc__list" data-docs-spy={@spy}>
      <li :for={entry <- @toc} class={entry.level == 3 && "docs-toc__sub"}>
        <a href={"#" <> entry.id}>{entry.title}</a>
      </li>
    </ul>
    """
  end

  # sobelow_skip ["XSS.Raw"]
  defp search_index, do: Phoenix.HTML.raw(Docs.search_index())
end
