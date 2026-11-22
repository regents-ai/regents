defmodule RegentsWeb.Autolaunch.AuctionsLive do
  @moduledoc """
  The auctions list, at `/autolaunch/auctions`: every auction as a table row
  with its FDV at the current price, bid volume and status, filtered by
  chain, status, search and the creator's verified connections, a page at a
  time (`RegentsWeb.Autolaunch.LiveListings`), under the Revstake and
  Memestock auction counts. The options live in the address
  (`RegentsWeb.Autolaunch.HomeMarket`).

  The counts and the dollar prices are read once, in the background, with
  the page's first listing and under its one spend of the address's list
  reads; when the allowance is spent the counts are unavailable and every
  figure is in its own currency.

  Still to come, each with its own part: the notices about reading the
  chains, the list rereading itself while the page is open, and the Claim and
  Refund presses on a finished auction the signed-in wallet bid in.
  """
  use RegentsWeb, :live_view

  import RegentsWeb.Autolaunch.Components.MarketCard, only: [auction_list: 1, list_tools: 1]
  import RegentsWeb.Autolaunch.Components.AuctionStats

  alias RegentsWeb.Autolaunch.{HomeMarket, LiveListings, PublicDocuments}

  @all %{state: "all", sort: "newest", x: false, ens: false, github: false}

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page("/autolaunch/auctions"))
     |> assign(client_tag: Map.fetch!(session, "client_tag"), all: @all)
     |> LiveListings.paged()}
  end

  def handle_params(params, _uri, socket) do
    options = params |> Map.put("view", "auctions") |> HomeMarket.options()

    {:noreply,
     socket
     |> assign(:pill, pill(options))
     |> LiveListings.filtered(options,
       revstake_stats: &Regents.Autolaunch.AuctionStats.revstake/0,
       memestock_stats: &Regents.Autolaunch.AuctionStats.memestock/0
     )}
  end

  def handle_event("search", params, socket),
    do: {:noreply, patch(socket, %{q: Map.get(params, "q", "")})}

  def handle_event("filter", params, socket) do
    changes =
      params
      |> Map.take(~w(chain state x ens github))
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

  defp list_path(options, changes), do: HomeMarket.path(options, changes, "/autolaunch/auctions")

  defp pill(options) do
    cond do
      options.state == "graduated" -> :graduated
      options.state == "active" and options.sort == "newest" -> :live
      options.state == "all" and not (options.x or options.ens or options.github) -> :all
      true -> nil
    end
  end

  defp verified?(options), do: options.x or options.ens or options.github

  # A search, a chain or a verified-creator choice narrows the list; a status
  # alone only picks which auctions to look at.
  defp searched?(options), do: options.q != "" or options.chain != "all" or verified?(options)

  defp empty_title("all"), do: "No auctions yet"
  defp empty_title("active"), do: "No live auctions"
  defp empty_title(_state), do: "No auctions with this status"

  defp empty_line("all"), do: "Auctions appear here once someone launches a token."
  defp empty_line("active"), do: "New auctions show here while bidding is open."
  defp empty_line(_state), do: "Try another status, or see every auction."

  # With nothing live, the way on is what already happened: graduated auctions
  # and launched tokens.
  defp empty_routes(%{state: "active"} = options, _all),
    do: [
      {list_path(options, %{state: "graduated"}), "See graduated auctions"},
      {~p"/autolaunch/tokens", "See tokens"}
    ]

  defp empty_routes(options, all), do: [{list_path(options, all), "See every auction"}]

  def render(assigns) do
    ~H"""
    <div class="autolaunch-page market-list-page" id="auctions-list">
      <.auction_stats revstake={@revstake_stats} memestock={@memestock_stats} />
      <header class="market-list__header">
        <h1 id="auctions-list-title">Auctions</h1>
        <Regent.Primitives.button
          :if={Regents.read_only?()}
          disabled
          title="Opens soon"
        >Launch auction</Regent.Primitives.button>
        <.link
          :if={!Regents.read_only?()}
          navigate="/autolaunch/create"
          class="rg-button rg-button--primary"
        ><span class="rg-button__label">Launch auction</span></.link>
      </header>

      <.list_tools kind="auctions" options={@options} />

      <nav class="market-list__pills" aria-label="Quick filters">
        <.link patch={list_path(@options, @all)} aria-current={if @pill == :all, do: "page"}>All</.link>
        <.link
          patch={list_path(@options, %{state: "active", sort: "newest"})}
          aria-current={if @pill == :live, do: "page"}
        >Live</.link>
        <.link
          patch={list_path(@options, %{state: "graduated"})}
          aria-current={if @pill == :graduated, do: "page"}
        >Graduated</.link>
      </nav>

      <section
        id="auctions-market"
        class="market-list"
        aria-labelledby="auctions-list-title"
        aria-busy={to_string(@loading)}
      >
        <p :if={@loading} class="visually-hidden" role="status">Loading auctions</p>

        <.auction_list
          :if={@records != [] or @loading}
          creators={@creators}
          records={@records}
          rates={@rates}
          loading={@loading}
        />

        <Regent.Primitives.notice :if={@failed} tone="error">
          <p>
            {if @append,
              do: "More auctions could not be loaded. The ones shown are still here.",
              else: "Auctions are unavailable right now."}
          </p>
          <Regent.Primitives.button phx-click="retry" variant="secondary">Retry</Regent.Primitives.button>
        </Regent.Primitives.notice>

        <div :if={!@loading && !@failed && @records == []} class="market-list__empty" role="status">
          <%= if searched?(@options) do %>
            <h2>No matching auctions</h2>
            <p>Try a different search, or clear your filters.</p>
            <.link
              patch={list_path(@options, Map.merge(@all, %{q: "", chain: "all"}))}
              class="rg-button rg-button--secondary"
            >Clear filters</.link>
          <% else %>
            <h2>{empty_title(@options.state)}</h2>
            <p>{empty_line(@options.state)}</p>
            <div :if={@options.state != "all"} class="market-list__routes">
              <.link
                :for={{path, label} <- empty_routes(@options, @all)}
                navigate={path}
                class="rg-button rg-button--secondary"
              >{label}</.link>
            </div>
            <.link
              :if={@options.state == "all" && !Regents.read_only?()}
              navigate="/autolaunch/create"
              class="rg-button rg-button--secondary"
            >Launch auction</.link>
            <.link
              :if={@options.state == "all" && Regents.read_only?()}
              navigate={~p"/autolaunch/how-it-works"}
              class="rg-button rg-button--secondary"
            >How it works</.link>
          <% end %>
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
