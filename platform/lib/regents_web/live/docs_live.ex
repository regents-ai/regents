defmodule RegentsWeb.DocsLive do
  @moduledoc """
  The developer docs inside the product shell: search, Ask AI, the section
  tabs, the docs sidebar, the page and its "On this page" list. The words come
  from `RegentsWeb.Docs`; no account or database reads. The `Docs` hook runs the
  search, the list that follows the reader, View as Markdown and the phone menu.
  """

  use RegentsWeb, :html

  alias Phoenix.LiveView.JS
  alias RegentsWeb.{Docs, Docs.Pages, PublicDocuments}

  @doc "What the docs page at `path` shows."
  def read(path) do
    page = Pages.page(path)
    {html, toc} = Docs.render(page)
    {name, description} = Docs.heading(page)
    {previous, next} = Pages.neighbours(page)
    sections = Pages.sections()
    {_, [first | _]} = List.keyfind(sections, page.section, 0)
    ask = "Read #{PublicDocuments.url(page.path)} so you can answer questions about it."

    %{
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
    }
  end

  attr :docs, :map, required: true

  def page(assigns) do
    ~H"""
    <div id={"docs-page-#{@docs.page.key || "overview"}"} class="docs" phx-hook="Docs">
      <div class="docs-bar">
        <header class="docs-top">
          <div id="docs-search" class="docs-search" role="search" phx-update="ignore">
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
              <a href={@docs.claude} target="_blank" rel="noopener noreferrer">Claude</a>
              <a href={@docs.chatgpt} target="_blank" rel="noopener noreferrer">ChatGPT</a>
            </div>
          </span>

          <Regent.Primitives.button
            variant="quiet"
            arrow={false}
            class="docs-menu-button"
            popovertarget="docs-nav"
          >
            Contents
          </Regent.Primitives.button>
        </header>

        <nav class="docs-tabs" aria-label="Sections">
          <.link
            :for={{section, [first | _]} <- @docs.sections}
            navigate={first.path}
            aria-current={if(section == @docs.page.section, do: "true")}
          >
            {section}
          </.link>
        </nav>
      </div>

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
            :for={{section, pages} <- @docs.sections}
            id={"docs-nav-" <> String.downcase(section)}
            class="docs-nav__group"
            open={section == @docs.page.section}
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <summary>{section}</summary>
            <ul>
              <li :for={page <- pages}>
                <.link
                  navigate={page.path}
                  aria-current={if(page.path == @docs.page.path, do: "page")}
                >
                  {page.name}
                </.link>
              </li>
            </ul>
          </details>
          <div class="docs-nav__foot">
            <a href={~p"/llms.txt"}>llms.txt</a>
            <a href={~p"/openapi.json"}>OpenAPI</a>
            <.link navigate={~p"/about"}>About</.link>
          </div>
        </nav>

        <article id="docs-article" class="docs-article" tabindex="-1">
          <nav class="docs-crumbs" aria-label="Breadcrumb">
            <ol>
              <li><.link navigate={~p"/docs"}>Docs</.link></li>
              <li :if={@docs.page.path != "/docs"}>
                <.link navigate={@docs.section_path}>{@docs.page.section}</.link>
              </li>
              <li><span aria-current="page">{@docs.name}</span></li>
            </ol>
          </nav>
          <h1 class="docs-title">{@docs.name}</h1>
          <p class="docs-lede">{@docs.description}</p>

          <div class="docs-actions">
            <Regent.Primitives.copy_button id="docs-copy" text={@docs.markdown} variant="quiet">
              Copy for LLM
            </Regent.Primitives.copy_button>
            <Regent.Primitives.button variant="quiet" arrow={false} data-docs-markdown>
              View as Markdown
            </Regent.Primitives.button>
            <.link navigate={~p"/start"} class="rg-button rg-button--primary">
              <span class="rg-button__label">Set up agent</span>
            </.link>
          </div>

          <details
            :if={@docs.toc != []}
            id="docs-toc-phone"
            class="docs-toc-phone"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <summary>On this page</summary>
            <.toc id="docs-toc-phone-list" toc={@docs.toc} />
          </details>

          <div class="docs-prose">{@docs.html}</div>

          <nav class="docs-pager" aria-label="More docs">
            <.link :if={@docs.previous} class="docs-pager__previous" navigate={@docs.previous.path}>
              <span>Previous</span>
              {@docs.previous.name}
            </.link>
            <.link :if={@docs.next} class="docs-pager__next" navigate={@docs.next.path}>
              <span>Next</span>
              {@docs.next.name}
            </.link>
          </nav>
        </article>

        <aside :if={@docs.toc != []} class="docs-toc" aria-labelledby="docs-toc-title">
          <p id="docs-toc-title" class="docs-toc__title">On this page</p>
          <.toc id="docs-toc-spy" toc={@docs.toc} spy />
        </aside>
      </div>

      <script type="application/json" id="docs-search-index">
        <%= search_index() %>
      </script>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :toc, :list, required: true
  attr :spy, :boolean, default: false

  # The list the reader follows is marked by the hook, so patches leave it alone.
  defp toc(assigns) do
    ~H"""
    <ul id={@id} class="docs-toc__list" data-docs-spy={@spy} phx-update={@spy && "ignore"}>
      <li :for={entry <- @toc} class={entry.level == 3 && "docs-toc__sub"}>
        <a href={"#" <> entry.id}>{entry.title}</a>
      </li>
    </ul>
    """
  end

  # sobelow_skip ["XSS.Raw"]
  defp search_index, do: Phoenix.HTML.raw(Docs.search_index())
end
