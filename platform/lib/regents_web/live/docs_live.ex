defmodule RegentsWeb.DocsLive do
  @moduledoc """
  Unified developer documentation for every Regents Labs product inside the
  product shell: cross-product search, Ask AI, product switcher tabs,
  product-scoped sidebar groups, the page, and its "On this page" list.

  Words come from `RegentsWeb.Docs`; no account or database reads. The `Docs`
  hook runs cross-product search, scrollspy TOC, Ask AI menu, and the mobile
  navigation drawer.
  """

  use RegentsWeb, :html

  alias Phoenix.LiveView.JS
  alias RegentsWeb.{Docs, Docs.Pages, PublicDocuments}

  # Order of product cards on the `/docs` overview hub (products in canonical
  # marketing order, followed by the shared Regents platform docs).
  @hub_product_order ~w(cloak techtree keyfleet autolaunch patchbay regents)

  @doc "What the docs page at `path` shows."
  def read(path) do
    page = Pages.page(path)
    product = Pages.product(page.product)
    products = Pages.products()
    {html, toc} = Docs.render(page)
    {name, description} = Docs.heading(page)
    {previous, next} = Pages.neighbours(page)
    ask = "Read #{PublicDocuments.url(page.path)} so you can answer questions about it."

    hub_cards =
      if page.path == "/docs" do
        Enum.map(@hub_product_order, fn id ->
          item = Pages.product(id)

          %{
            id: item.id,
            name: item.name,
            tagline: item.tagline,
            path: if(id == "regents", do: "/docs/pairing", else: item.home_path),
            count_label: page_count_label(item.page_count)
          }
        end)
      else
        []
      end

    %{
      page: page,
      dom_id: "docs-page-" <> String.replace(page.key || "overview", "/", "-"),
      product: product,
      products: products,
      hub_cards: hub_cards,
      html: html,
      toc: toc,
      markdown: Docs.markdown(page),
      markdown_path: page.path <> ".md",
      name: name,
      heading: if(page.path == "/docs", do: "Regents Labs Docs", else: name),
      description: description,
      previous: previous,
      next: next,
      claude: "https://claude.ai/new?" <> URI.encode_query(q: ask),
      chatgpt: "https://chatgpt.com/?" <> URI.encode_query(q: ask)
    }
  end

  defp page_count_label(1), do: "1 page"
  defp page_count_label(count), do: "#{count} pages"

  attr :docs, :map, required: true

  def page(assigns) do
    ~H"""
    <div
      id={@docs.dom_id}
      class="docs"
      data-docs-product={@docs.product.id}
      phx-hook="Docs"
    >
      <div class="docs-bar">
        <header class="docs-top">
          <div id="docs-search" class="docs-search" role="search" phx-update="ignore">
            <label class="visually-hidden" for="docs-search-input">Search all docs</label>
            <input
              id="docs-search-input"
              type="search"
              placeholder="Search all product docs"
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
            <Regent.Primitives.button
              id="docs-ask-trigger"
              variant="secondary"
              arrow={false}
              popovertarget="docs-ask-menu"
              aria-haspopup="menu"
              aria-controls="docs-ask-menu"
              aria-expanded="false"
            >
              Ask AI
            </Regent.Primitives.button>
            <div id="docs-ask-menu" class="docs-menu" role="menu" popover>
              <a href={@docs.claude} role="menuitem" target="_blank" rel="noopener noreferrer">
                Claude
              </a>
              <a href={@docs.chatgpt} role="menuitem" target="_blank" rel="noopener noreferrer">
                ChatGPT
              </a>
            </div>
          </span>

          <Regent.Primitives.button
            id="docs-menu-trigger"
            variant="quiet"
            arrow={false}
            class="docs-menu-button"
            popovertarget="docs-nav"
            aria-controls="docs-nav"
            aria-expanded="false"
          >
            Contents
          </Regent.Primitives.button>
        </header>

        <nav class="docs-tabs" aria-label="Products">
          <.link
            :for={product <- @docs.products}
            navigate={product.home_path}
            class="docs-tabs__item"
            data-docs-product={product.id}
            aria-current={if(product.id == @docs.product.id, do: "true")}
          >
            <span class="docs-product-dot" aria-hidden="true"></span>
            {product.name}
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

          <div class="docs-nav__product" data-docs-product={@docs.product.id}>
            <span class="docs-nav__product-title">
              <span class="docs-product-dot" aria-hidden="true"></span>
              {@docs.product.name}
            </span>
            <a class="docs-nav__product-link" href={@docs.product.product_url}>
              {@docs.product.product_label}
            </a>
          </div>

          <details
            :for={group <- @docs.product.groups}
            id={"docs-nav-#{@docs.product.id}-#{group.slug}"}
            class="docs-nav__group"
            open
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <summary>{group.name}</summary>
            <ul>
              <li :for={page <- group.pages}>
                <.link
                  navigate={page.path}
                  aria-current={if(page.path == @docs.page.path, do: "page")}
                >
                  {page.name}
                </.link>
              </li>
            </ul>
          </details>

          <div class="docs-nav__products" aria-label="Switch product">
            <p class="docs-nav__products-label">Products</p>
            <ul>
              <li :for={product <- @docs.products}>
                <.link
                  navigate={product.home_path}
                  data-docs-product={product.id}
                  aria-current={if(product.id == @docs.product.id, do: "true")}
                >
                  <span class="docs-product-dot" aria-hidden="true"></span>
                  {product.name}
                </.link>
              </li>
            </ul>
          </div>

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
                <.link navigate={@docs.product.home_path}>{@docs.product.name}</.link>
              </li>
              <li><span aria-current="page">{@docs.name}</span></li>
            </ol>
          </nav>

          <h1 class="docs-title">{@docs.heading}</h1>
          <p class="docs-lede">{@docs.description}</p>

          <div class="docs-actions">
            <Regent.Primitives.copy_button id="docs-copy" text={@docs.markdown} variant="quiet">
              Copy for LLM
            </Regent.Primitives.copy_button>
            <a
              href={@docs.markdown_path}
              target="_blank"
              rel="noopener noreferrer"
              class="rg-button rg-button--quiet"
              data-docs-markdown
            >
              <span class="rg-button__label">View as Markdown</span>
            </a>
            <a href={@docs.product.app_path} class="rg-button rg-button--primary">
              <span class="rg-button__label">{@docs.product.app_label}</span>
            </a>
          </div>

          <section :if={@docs.hub_cards != []} class="docs-hub" aria-label="Products">
            <.link
              :for={card <- @docs.hub_cards}
              navigate={card.path}
              class="docs-hub__card"
              data-docs-product={card.id}
            >
              <span class="docs-hub__head">
                <span class="docs-hub__name">
                  <span class="docs-product-dot" aria-hidden="true"></span>
                  {card.name}
                </span>
                <span class="docs-hub__count">{card.count_label}</span>
              </span>
              <span class="docs-hub__tagline">{card.tagline}</span>
            </.link>
          </section>

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

          <nav :if={@docs.previous || @docs.next} class="docs-pager" aria-label="More docs">
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
