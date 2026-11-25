defmodule RegentsWeb.Autolaunch.TokensLive do
  @moduledoc """
  The tokens list, at `/autolaunch/tokens`: every launched token as a table
  row with its price, market cap and when it launched, filtered by chain,
  search and the creator's verified connections, a page at a time
  (`RegentsWeb.Autolaunch.LiveListings`). The options live in the address
  (`RegentsWeb.Autolaunch.HomeMarket`).

  The dollar prices are read once, in the background, with the page's first
  listing and under its one spend of the address's list reads; until they
  arrive, and when the allowance is spent, every figure is in its own
  currency.

  Still to come, each with its own part: the notices about reading the
  chains and the list rereading itself while the page is open.
  """
  use RegentsWeb, :live_view

  import RegentsWeb.Autolaunch.Components.MarketCard, only: [token_list: 1, list_tools: 1]

  alias RegentsWeb.Autolaunch.{HomeMarket, LiveListings, PublicDocuments}

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page("/autolaunch/tokens"))
     |> assign(:client_tag, Map.fetch!(session, "client_tag"))
     |> LiveListings.paged()}
  end

  def handle_params(params, _uri, socket) do
    options = params |> Map.put("view", "tokens") |> HomeMarket.options()
    {:noreply, LiveListings.filtered(socket, options)}
  end

  def handle_event("filter", params, socket) do
    changes =
      params
      |> Map.take(~w(chain x ens github))
      |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)

    {:noreply, patch(socket, changes)}
  end

  def handle_event("load-more", _params, %{assigns: %{loading: false, has_more: true}} = socket),
    do: {:noreply, LiveListings.load(socket, true)}

  def handle_event("load-more", _params, socket), do: {:noreply, socket}

  # Retry reads only what failed: a press with nothing failed, or while the
  # read is under way, starts none.
  def handle_event("retry", _params, %{assigns: %{failed: true, loading: false}} = socket),
    do: {:noreply, LiveListings.load(socket, socket.assigns.append)}

  def handle_event("retry", _params, socket), do: {:noreply, socket}

  # An event no control on this page sends changes nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp patch(socket, changes),
    do: push_patch(socket, to: list_path(socket.assigns.options, changes))

  defp list_path(options, changes), do: HomeMarket.path(options, changes, "/autolaunch/tokens")

  defp filtered?(options),
    do: options.q != "" or options.chain != "all" or options.x or options.ens or options.github

  def render(assigns) do
    ~H"""
    <div class="autolaunch-page market-list-page" id="tokens-list">
      <header class="market-list__header">
        <h1 id="tokens-list-title">Tokens</h1>
      </header>

      <.list_tools kind="tokens" options={@options} />

      <section
        id="tokens-market"
        class="market-list"
        aria-labelledby="tokens-list-title"
        aria-busy={to_string(@loading)}
      >
        <p :if={@loading} class="visually-hidden" role="status">Loading tokens</p>

        <.token_list
          :if={@records != [] or @loading}
          creators={@creators}
          records={@records}
          rates={@rates}
          loading={@loading}
        />

        <Regent.Primitives.notice :if={@failed} tone="error">
          <p>
            {if @append,
              do: "More tokens could not be loaded. The ones shown are still here.",
              else: "Tokens are unavailable right now."}
          </p>
          <Regent.Primitives.button phx-click="retry" variant="secondary">Retry</Regent.Primitives.button>
        </Regent.Primitives.notice>

        <div :if={!@loading && !@failed && @records == []} class="market-list__empty" role="status">
          <h2>{if filtered?(@options), do: "No matching tokens", else: "No tokens yet"}</h2>
          <p>
            {if filtered?(@options),
              do: "Try a different search, or clear your filters.",
              else: "Tokens appear here once their auction launches."}
          </p>
          <.link
            :if={filtered?(@options)}
            patch={list_path(@options, %{q: "", chain: "all", x: false, ens: false, github: false})}
            class="rg-button rg-button--secondary"
          >Clear filters</.link>
          <.link
            :if={!filtered?(@options)}
            navigate={~p"/autolaunch/auctions"}
            class="rg-button rg-button--secondary"
          >
            Browse auctions
          </.link>
        </div>

        <div :if={@has_more && !@failed} class="market-list__more">
          <Regent.Primitives.button phx-click="load-more" disabled={@loading} variant="secondary">
            {if @loading, do: "Loading…", else: "Load more"}
          </Regent.Primitives.button>
        </div>
      </section>
    </div>
    """
  end
end
