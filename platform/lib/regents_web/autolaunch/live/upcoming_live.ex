defmodule RegentsWeb.Autolaunch.UpcomingLive do
  @moduledoc """
  Stocks on Base and Robinhood, as a short list: each stock token is named with
  its issuer and chain and links to its own page (`RegentsWeb.Autolaunch.StockLive`)
  with its addresses, links and dated pool research. The established Available to Pair list is preserved; new research
  remains in its preview sections and never changes launchpad admission.

  Above the lists, the stock products as the home page's cards: Memestock and
  covered calls.
  """
  use RegentsWeb, :live_view

  import RegentsWeb.Autolaunch.Components.HomeProducts, only: [product_cards: 1]
  import RegentsWeb.Autolaunch.Components.StockIdentity, only: [stock_identity: 1]
  import RegentsWeb.Autolaunch.Components.StockSelect, only: [stock_logo: 1]

  alias Regents.Autolaunch.Stocks.UpcomingCatalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, RegentsWeb.Autolaunch.PublicDocuments.page("/autolaunch/stocks"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = UpcomingCatalog.filters(params)
    filters = Map.merge(%{q: "", chain: "", availability: ""}, query)
    chains = UpcomingCatalog.search(filters.q, filters.chain, filters.availability)

    count =
      Enum.sum_by(chains, fn chain ->
        length(chain.available) + length(chain.eligible) + length(chain.feed_required)
      end)

    {:noreply, assign(socket, filters: filters, query: query, chains: chains, count: count)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/autolaunch/stocks?#{UpcomingCatalog.filters(params)}")}
  end

  defp columns(chains, _key, query) when map_size(query) == 0, do: chains
  defp columns(chains, key, _query), do: Enum.reject(chains, &(Map.fetch!(&1, key) == []))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fact-page upcoming">
      <header class="autolaunch-heading">
        <h1>Onchain Stocks</h1>
      </header>

      <.product_cards
        launches_open={!Regents.Autolaunch.Prelaunch.read_only?()}
        only={~w(memestock calls)}
      />

      <form
        id="stock-directory-filters"
        class="upcoming__filters"
        phx-submit="filter"
        action={~p"/autolaunch/stocks"}
        method="get"
      >
        <label>
          <span>Search stocks</span>
          <input type="search" name="q" value={@filters.q} placeholder="Name, ticker or address" />
        </label>
        <label>
          <span>Network</span>
          <span class="rg-select">
            <select name="chain">
              <option value="" selected={@filters.chain == ""}>All networks</option>
              <option value="base" selected={@filters.chain == "base"}>Base</option>
              <option value="robinhood" selected={@filters.chain == "robinhood"}>Robinhood</option>
            </select>
          </span>
        </label>
        <label>
          <span>Availability</span>
          <span class="rg-select">
            <select name="availability">
              <option value="" selected={@filters.availability == ""}>All stocks</option>
              <option value="available" selected={@filters.availability == "available"}>
                Available to Pair
              </option>
              <option value="soon" selected={@filters.availability == "soon"}>Soon Available</option>
              <option value="feed_required" selected={@filters.availability == "feed_required"}>
                Feed Required
              </option>
            </select>
          </span>
        </label>
        <button class="rg-button" type="submit">Apply</button>
        <.link
          :if={@filters.q != "" or @filters.chain != "" or @filters.availability != ""}
          patch={~p"/autolaunch/stocks"}
        >Reset</.link>
      </form>
      <p id="stock-directory-count" role="status">
        {if @count == 0,
          do: "No stocks match these filters.",
          else: "#{@count} #{if @count == 1, do: "stock", else: "stocks"}"}
      </p>

      <section
        :if={@count > 0 and columns(@chains, :eligible, @query) != []}
        class="fact-page__section"
        aria-labelledby="upcoming-eligible"
      >
        <h2 id="upcoming-eligible">Soon Available</h2>
        <div class="upcoming__columns">
          <.column
            :for={chain <- columns(@chains, :eligible, @query)}
            id={"upcoming-eligible-#{chain.chain}"}
            query={@query}
            chain={chain}
            stocks={chain.eligible}
          />
        </div>
      </section>

      <section
        :if={@count > 0 and columns(@chains, :available, @query) != []}
        class="fact-page__section"
        aria-labelledby="upcoming-available"
      >
        <h2 id="upcoming-available" class="upcoming__pairing">
          <span>Available to Pair:</span>
          <a href="/autolaunch/create" class="standalone-link">Memestock</a>
          <span aria-hidden="true">|</span>
          <span
            class="upcoming__pairing-soon"
            title="Coming soon"
            aria-label="Dual Stock Token: Coming soon"
            tabindex="0"
          >Dual Stock Token</span>
        </h2>
        <div class="upcoming__columns">
          <.column
            :for={chain <- columns(@chains, :available, @query)}
            id={"upcoming-available-#{chain.chain}"}
            query={@query}
            chain={chain}
            stocks={chain.available}
          />
        </div>
      </section>

      <section
        :if={@count > 0 and columns(@chains, :feed_required, @query) != []}
        class="fact-page__section"
        aria-labelledby="upcoming-feed-required"
      >
        <h2 id="upcoming-feed-required">Feed Required</h2>
        <div class="upcoming__columns">
          <.column
            :for={chain <- columns(@chains, :feed_required, @query)}
            id={"upcoming-feed-required-#{chain.chain}"}
            query={@query}
            chain={chain}
            stocks={chain.feed_required}
          />
        </div>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :chain, :map, required: true
  attr :stocks, :list, required: true
  attr :query, :map, required: true

  defp column(assigns) do
    ~H"""
    <section class={"upcoming-column upcoming-column--#{@chain.chain}"} aria-labelledby={@id}>
      <h3 id={@id}><span>{@chain.name}</span><span>{length(@stocks)}</span></h3>
      <ul :if={@stocks != []} class="upcoming-column__stocks">
        <li :for={stock <- @stocks}>
          <.link
            navigate={~p"/autolaunch/stocks/#{stock["symbol"]}?#{@query}"}
            class="upcoming-stock"
            aria-label={"#{stock["symbol"]} on #{@chain.name}: stock details"}
          >
            <.stock_logo stock={%{symbol: stock["symbol"]}} />
            <span class="stock-select__symbol">{stock["symbol"]}</span>
            <span class="stock-select__name">{stock["name"]}</span>
            <.stock_identity :if={stock["token_address"]} chain={@chain.chain} />
            <span :if={!stock["token_address"]} class="stock-select__identity">
              {@chain.name} · Pending verification
            </span>
          </.link>
        </li>
      </ul>
      <p :if={@stocks == []} class="upcoming-column__none">None right now.</p>
    </section>
    """
  end
end
