defmodule RegentsWeb.Autolaunch.HomeLive do
  @moduledoc """
  Autolaunch's home, at `/autolaunch`: the auctions or the launched tokens, as
  a list or a gallery, with the list's switch, Filter and the token types, a
  page at a time. The options live in the address
  (`RegentsWeb.Autolaunch.HomeMarket`), so a choice changes the list without
  a full load and back and forward restore it.

  Still to come, each with its own part: the product cards above the lists,
  Coming next, Bid volume and Principles below them, the Calls list, the
  notices about reading the chains, the lists rereading themselves while the
  page is open, and every wallet press (Bid, Buy, Claim and Refund).
  """
  use RegentsWeb, :live_view

  import RegentsWeb.Autolaunch.Components.MarketCard,
    only: [auction_list: 1, token_list: 1, explore_card: 1, connections_for: 2]

  import RegentsWeb.Autolaunch.Components.ChainIcon
  import RegentsWeb.Autolaunch.Components.LinkIcon
  alias Regents.Autolaunch.Lab
  alias RegentsWeb.Autolaunch.{HomeMarket, PublicDocuments}

  # What the list shows: auctions or launched tokens. Tokens choose a type
  # below it.
  @lists [auctions: "Auctions", tokens: "Tokens"]
  @token_kinds [
    {"all", "All"},
    {"memestock", "Memestock"},
    {"revstake", "Revstake"}
  ]

  # An auction's status in the filter menu. Each is a set of list options.
  @statuses [new: "All", live: "Live", finished: "Finished"]

  @unfiltered %{q: "", chain: "all", kind: "all", x: false, ens: false, github: false}

  @no_connection %{x: false, ens: false, github: false}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page("/autolaunch"))
     |> assign(
       market_options: nil,
       records: [],
       records_kind: :auction,
       creators: %{},
       market_loading: true,
       market_failed: false,
       market_append: false,
       next_cursor: nil,
       has_more: false,
       local_lab: Lab.test_chain?(),
       listed: nil,
       lists: @lists,
       token_kinds: @token_kinds,
       statuses: @statuses,
       unfiltered: @unfiltered,
       no_connection: @no_connection
     )}
  end

  def handle_params(params, _uri, socket) do
    options = HomeMarket.options(params)

    {:noreply,
     socket
     |> assign(
       market_options: options,
       list: list(params),
       token_kind: options.kind,
       kind: kind(options),
       tab: tab(options),
       filtered?: filtered?(options),
       filter_active?: filter_active?(options),
       connections: Map.take(options, [:x, :ens, :github])
     )
     |> show_market()}
  end

  # The list the address names.
  defp list(%{"view" => "tokens"}), do: :tokens
  defp list(_params), do: :auctions

  # The auctions or tokens the options name, read unless they are the ones
  # already shown.
  defp show_market(%{assigns: %{listed: nil}} = socket), do: first_market(socket)

  defp show_market(socket) do
    if Map.drop(socket.assigns.listed, [:display]) ==
         Map.drop(socket.assigns.market_options, [:display]),
       do: socket,
       else: load_market(socket, false)
  end

  def handle_event(
        "load-more",
        _params,
        %{assigns: %{market_loading: false, has_more: true}} = socket
      ),
      do: {:noreply, load_market(socket, true)}

  def handle_event("load-more", _params, socket), do: {:noreply, socket}

  # "Try again" reads only what failed: a press with nothing failed, or while
  # the read is under way, starts none.
  def handle_event(
        "retry",
        _params,
        %{assigns: %{market_failed: true, market_loading: false}} = socket
      ),
      do: {:noreply, load_market(socket, socket.assigns.market_append)}

  def handle_event("retry", _params, socket), do: {:noreply, socket}

  def handle_async(:home_market, {:ok, {:ok, page}}, socket),
    do: {:noreply, put_market(socket, page)}

  def handle_async(:home_market, _failure, socket), do: {:noreply, market_failed(socket)}

  # The cards already shown stay until the new listing arrives and replaces
  # them, so changing a setting never blanks the gallery.
  defp load_market(socket, append?) do
    options = socket.assigns.market_options
    cursor = if append?, do: socket.assigns.next_cursor

    socket
    |> assign(
      listed: options,
      market_loading: true,
      market_failed: false,
      market_append: append?
    )
    |> start_async(:home_market, fn -> read_market(options, cursor) end)
  end

  # The page's first listing is read before it is shown, so the coins are in
  # the page as it arrives, for readers that run no scripts too. Later
  # listings load beside the ones already shown.
  defp first_market(socket) do
    socket = assign(socket, market_append: false, listed: socket.assigns.market_options)

    case read_market(socket.assigns.market_options, nil) do
      {:ok, page} -> put_market(socket, page)
      _failure -> market_failed(socket)
    end
  end

  defp read_market(options, cursor) do
    with {:ok, page} <- HomeMarket.read(options, cursor),
         {:ok, creators} <- Regents.Autolaunch.HomeMarket.creators(page.records) do
      {:ok, Map.put(page, :creators, creators)}
    end
  end

  defp put_market(socket, page) do
    records =
      if socket.assigns.market_append,
        do: Enum.uniq_by(socket.assigns.records ++ page.records, & &1.id),
        else: page.records

    creators =
      if socket.assigns.market_append,
        do: Map.merge(socket.assigns.creators, page.creators),
        else: page.creators

    assign(socket,
      records: records,
      records_kind: kind(socket.assigns.listed),
      creators: creators,
      next_cursor: page.next_cursor,
      has_more: page.has_more,
      market_loading: false,
      market_failed: false
    )
  end

  # A failed "Load more" keeps what is shown; a failed new listing clears the
  # previous one, which no longer matches what was asked for.
  defp market_failed(%{assigns: %{market_append: true}} = socket),
    do: assign(socket, market_loading: false, market_failed: true)

  defp market_failed(socket) do
    assign(socket,
      records: [],
      creators: %{},
      next_cursor: nil,
      has_more: false,
      market_loading: false,
      market_failed: true
    )
  end

  defp kind(%{view: "tokens"}), do: :token
  defp kind(_options), do: :auction

  attr :patch, :string, required: true
  attr :selected, :boolean, required: true
  attr :label, :string, default: nil, doc: "the option's name when it shows only a logo"
  slot :inner_block, required: true

  # One choice in the filter menu: a tick marks the chosen one in its group.
  defp filter_option(assigns) do
    ~H"""
    <.link
      patch={@patch}
      class="home-filter__option"
      aria-current={if @selected, do: "true"}
      aria-label={@label}
      title={@label}
    >
      <Regent.Icons.icon name="check" class="home-filter__check" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp tab(%{view: "tokens"}), do: :tokens
  defp tab(%{state: "all"}), do: :new
  defp tab(%{state: "active"}), do: :live
  defp tab(%{state: "finished"}), do: :finished
  defp tab(_options), do: nil

  defp tab_options(:new), do: %{view: "auctions", state: "all", sort: "newest"}
  defp tab_options(:live), do: %{view: "auctions", state: "active", sort: "ending"}
  defp tab_options(:finished), do: %{view: "auctions", state: "finished", sort: "newest"}
  defp tab_options(:tokens), do: %{view: "tokens"}

  defp filtered?(options),
    do:
      options.q != "" or options.chain != "all" or options.kind != "all" or options.x or
        options.ens or options.github

  # Whether the filter menu narrows the list: tokens choose their type beside
  # it, not in it.
  defp filter_active?(%{view: "tokens"} = options),
    do: options.chain != "all" or options.x or options.ens or options.github

  defp filter_active?(options),
    do:
      options.chain != "all" or options.kind != "all" or options.state != "all" or options.x or
        options.ens or options.github

  # The way in to launching. Before launches open it stays in place, switched
  # off, with the reason beside it.
  defp launch_button(assigns) do
    ~H"""
    <.link
      :if={!Regents.read_only?()}
      navigate="/autolaunch/create"
      class="rg-button rg-button--secondary home-launch"
    >Launch yours</.link>
    <span :if={Regents.read_only?()} class="home-launch">
      <Regent.Primitives.button variant="secondary" disabled class="create-button">Launch yours</Regent.Primitives.button>
      <small>Opens soon</small>
    </span>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="home-page home-explore-page" id="home-explore">
      <h1 class="visually-hidden">Autolaunch</h1>

      <div class="home-toolbar">
        <nav
          id="home-lists"
          class="home-switch"
          aria-label="List"
          phx-hook="MotionTabs"
          data-active={@list}
          data-variant={RegentsWeb.Motion.standard("tabs")}
        >
          <span
            id="home-lists-ink"
            class="home-switch__ink"
            data-ink
            aria-hidden="true"
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["style"])}
          ></span>
          <.link
            :for={{list, label} <- @lists}
            patch={list_path(@market_options, list)}
            data-tab={list}
            aria-current={if @list == list, do: "page"}
          >{label}</.link>
        </nav>
        <span :if={@local_lab} class="home-network">
          {Lab.label()} · test assets
        </span>
        <%!-- Always in the page, so its coming and going never moves Filter, which has the
             keyboard after Clear search. --%>
        <p class="home-search-context" hidden={@market_options.q == ""}>
          <span>Results for “{@market_options.q}”</span>
          <button
            type="button"
            phx-click={
              [to: "#home-filters summary"]
              |> Phoenix.LiveView.JS.focus()
              |> Phoenix.LiveView.JS.patch(HomeMarket.path(@market_options, %{q: ""}))
            }
          >
            Clear search
          </button>
        </p>
        <details
          id="home-filters"
          class="home-filter"
          phx-hook=".FilterMenu"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["open"])}
        >
          <summary>
            Filter<span
              :if={@filter_active? and @market_options.q == ""}
              class="home-filter__active"
              aria-label="Filter active"
            ></span>
          </summary>
          <div
            class="home-filter__panel"
            data-panel="menu"
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["style"])}
          >
            <div class="home-filter__group" role="group" aria-label="Network">
              <span class="home-filter__label" aria-hidden="true">Network</span>
              <div class="home-filter__row">
                <.filter_option
                  patch={HomeMarket.path(@market_options, %{chain: "all"})}
                  selected={@market_options.chain == "all"}
                >
                  All
                </.filter_option>
                <.filter_option
                  :for={chain <- [:base, :robinhood]}
                  patch={HomeMarket.path(@market_options, %{chain: Atom.to_string(chain)})}
                  selected={@market_options.chain == Atom.to_string(chain)}
                >
                  <.chain_icon chain={chain} />
                </.filter_option>
              </div>
            </div>
            <div :if={@kind == :auction} class="home-filter__group" role="group" aria-label="Status">
              <span class="home-filter__label" aria-hidden="true">Status</span>
              <div class="home-filter__row">
                <.filter_option
                  :for={{status, label} <- @statuses}
                  patch={HomeMarket.path(@market_options, tab_options(status))}
                  selected={@tab == status}
                >
                  {label}
                </.filter_option>
              </div>
            </div>
            <div :if={@kind == :auction} class="home-filter__group" role="group" aria-label="Type">
              <span class="home-filter__label" aria-hidden="true">Type</span>
              <div class="home-filter__row">
                <.filter_option
                  :for={
                    {value, label} <- [
                      {"all", "All"},
                      {"revstake", "Revstake"},
                      {"memestock", "Memestock"}
                    ]
                  }
                  patch={HomeMarket.path(@market_options, %{kind: value})}
                  selected={@market_options.kind == value}
                >
                  {label}
                </.filter_option>
              </div>
            </div>
            <div class="home-filter__group" role="group" aria-label="Creator verified">
              <span class="home-filter__label" aria-hidden="true">Creator verified</span>
              <div class="home-filter__row">
                <.filter_option
                  patch={HomeMarket.path(@market_options, @no_connection)}
                  selected={@connections == @no_connection}
                >
                  Any
                </.filter_option>
                <.filter_option
                  :for={{key, label} <- [x: "X", ens: "ENS", github: "GitHub"]}
                  patch={HomeMarket.path(@market_options, %{@no_connection | key => true})}
                  selected={@connections == %{@no_connection | key => true}}
                  label={label}
                >
                  <.link_icon kind={key} />
                </.filter_option>
              </div>
            </div>
          </div>
        </details>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".FilterMenu">
          export default {
            mounted() {
              this.outside = (event) => {
                if (this.el.open && !this.el.contains(event.target)) this.el.open = false
              }
              this.escape = (event) => {
                if (event.key !== "Escape" || !this.el.open) return
                this.el.open = false
                this.el.querySelector("summary").focus()
              }
              document.addEventListener("pointerdown", this.outside)
              document.addEventListener("keydown", this.escape)
            },
            destroyed() {
              document.removeEventListener("pointerdown", this.outside)
              document.removeEventListener("keydown", this.escape)
            }
          }
        </script>
        <nav class="home-display" aria-label="Display">
          <.link
            patch={HomeMarket.path(@market_options, %{display: "list"})}
            aria-current={if @market_options.display == "list", do: "page"}
            aria-label="List"
            title="List"
          >
            <Regent.Icons.icon name="list" />
          </.link>
          <.link
            patch={HomeMarket.path(@market_options, %{display: "grid"})}
            aria-current={if @market_options.display == "grid", do: "page"}
            aria-label="Grid"
            title="Grid"
          >
            <Regent.Icons.icon name="layout-grid" />
          </.link>
        </nav>
      </div>

      <nav
        :if={@list == :tokens}
        id="home-kinds"
        class="home-switch home-switch--kinds"
        aria-label="Token type"
        phx-hook="MotionTabs"
        data-active={@token_kind}
        data-variant={RegentsWeb.Motion.standard("tabs")}
      >
        <span
          id="home-kinds-ink"
          class="home-switch__ink"
          data-ink
          aria-hidden="true"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["style"])}
        ></span>
        <.link
          :for={{kind, label} <- @token_kinds}
          patch={kind_path(@market_options, kind)}
          data-tab={kind}
          aria-current={if @token_kind == kind, do: "page"}
        >{label}</.link>
      </nav>

      <section
        id="home-market"
        class="home-market"
        aria-label="Launches"
        aria-busy={to_string(@market_loading)}
      >
        <div
          :if={@market_loading && @records == [] && @market_options.display == "grid"}
          class="home-coin-grid home-skeletons"
          aria-hidden="true"
        >
          <div :for={index <- 1..12} id={"home-skeleton-#{index}"} class="home-skeleton">
            <div class="loading-block home-skeleton__image"></div><div class="loading-block home-skeleton__line">
            </div><div class="loading-block home-skeleton__line home-skeleton__line--short"></div>
          </div>
        </div>
        <p :if={@market_loading} class="visually-hidden" role="status">Loading launches</p>

        <div
          :if={@records != [] && @market_options.display == "grid"}
          id="home-coin-grid"
          class="home-coin-grid"
          phx-hook="MotionCascade"
          data-variant={RegentsWeb.Motion.standard("grid")}
        >
          <.explore_card
            :for={{record, index} <- Enum.with_index(@records)}
            kind={@records_kind}
            record={record}
            lead={index == 0}
            creator_connections={connections_for(record, @creators)}
          />
        </div>
        <.auction_list
          :if={
            @market_options.display == "list" && @kind == :auction &&
              (@records != [] || @market_loading)
          }
          creators={@creators}
          records={if @records_kind == :auction, do: @records, else: []}
          loading={@market_loading}
        />
        <.token_list
          :if={
            @market_options.display == "list" && @kind == :token &&
              (@records != [] || @market_loading)
          }
          creators={@creators}
          records={if @records_kind == :token, do: @records, else: []}
          loading={@market_loading}
        />

        <Regent.Primitives.notice :if={@market_failed} tone="error" class="home-market__error">
          <p>
            {if @market_append,
              do: "More launches could not be loaded. The ones shown are still here.",
              else: "Launches can't be shown right now."}
          </p>
          <Regent.Primitives.button phx-click="retry" variant="secondary">Try again</Regent.Primitives.button>
        </Regent.Primitives.notice>
        <div
          :if={!@market_loading && !@market_failed && @records == []}
          class="home-empty"
          role="status"
        >
          <%= cond do %>
            <% @filtered? -> %>
              <h2>Nothing matches</h2>
              <p>Try another name, ticker, address or creator, or clear the filters.</p>
              <.link
                patch={HomeMarket.path(@market_options, @unfiltered)}
                class="rg-button rg-button--secondary"
              >Clear filters</.link>
            <% @tab in [:live, :finished, :tokens] -> %>
              <h2>{empty_title(@tab)}</h2>
              <p>{empty_line(@tab)}</p>
              <div class="home-empty__routes">
                <.link
                  :for={{tab, label} <- empty_routes(@tab)}
                  patch={HomeMarket.path(@market_options, tab_options(tab))}
                  class="rg-button rg-button--secondary"
                >{label}</.link>
              </div>
            <% true -> %>
              <h2>No launches yet</h2>
              <p>Be the first: a token you launch opens here for bids.</p>
              <.launch_button />
          <% end %>
        </div>
        <div :if={@has_more && !@market_failed} class="home-load-more">
          <Regent.Primitives.button
            phx-click="load-more"
            disabled={@market_loading}
            variant="secondary"
          >{if @market_loading, do: "Loading…", else: "Load more"}</Regent.Primitives.button>
        </div>
        <p
          :if={!@market_loading && !@market_failed && @records != []}
          class="home-result-count"
          role="status"
        >
          Showing {count_label(length(@records), @records_kind)}{if !@has_more,
            do: " · All results loaded"}
        </p>
      </section>
    </div>
    """
  end

  # A list keeps the filters that apply to it; its type starts again at All.
  defp list_path(options, list),
    do: HomeMarket.path(options, %{view: to_string(list), kind: "all"})

  defp kind_path(options, kind), do: HomeMarket.path(options, %{view: "tokens", kind: kind})

  defp empty_title(:live), do: "Nothing is live right now."
  defp empty_title(:finished), do: "No auction has finished yet."
  defp empty_title(:tokens), do: "No tokens have launched yet."

  defp empty_line(:live), do: "New auctions show here while bidding is open."
  defp empty_line(:finished), do: "Auctions show here once their bidding closes."
  defp empty_line(:tokens), do: "Tokens appear here once their auction launches."

  # With nothing live, the way on is what already happened: finished auctions
  # and launched tokens.
  defp empty_routes(:live), do: [finished: "See finished auctions", tokens: "See tokens"]
  defp empty_routes(_tab), do: [new: "See every launch"]

  defp count_label(1, :token), do: "1 token"
  defp count_label(count, :token), do: "#{count} tokens"
  defp count_label(1, _kind), do: "1 auction"
  defp count_label(count, _kind), do: "#{count} auctions"
end
