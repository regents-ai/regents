defmodule RegentsWeb.Autolaunch.HomeLive do
  @moduledoc """
  Autolaunch's home, at `/autolaunch`: the auctions or the launched tokens, as
  a list or a gallery, with the list's switch, Filter and the token types, a
  page at a time. The options live in the address
  (`RegentsWeb.Autolaunch.HomeMarket`), so a choice changes the list without
  a full load and back and forward restore it.

  Opening the page is one of its address's reads of the site, as any page is.
  Each listing the open page then reads (its first, a changed option, a
  search, Load more) spends one of that address's `:autolaunch_list_reads`
  (`RegentsWeb.Autolaunch.LiveListings.admit/1`, the list pages' rule too);
  past the allowance the page says the launches can't be
  shown, with Try again. Load more keeps every row it has read in the page's
  memory, to be changed before either list holds 1,000 rows: see SOURCE.json.

  Below the list, whatever it shows: Coming next (up to three auctions taking
  bids, the soonest to close first, then those opening soon), Bid volume (up
  to six launches with the most put in by bidders) and Principles (what
  Autolaunch holds to, as value cards). The two rows are read once, with the
  page's first listing and under its one spend of the allowance. Each row is
  what its read answered, rows or none; when its read fails, or the allowance
  is spent, the row is not known and is left out.

  Prices, FDVs and market caps are in dollars where the price of their
  currency is known (`Regents.Autolaunch.UsdRates`), otherwise in that
  currency. The prices are read once, in the background, with the open
  page's first listing and under the same spend; until they arrive, and when
  the allowance is spent, every figure is in its own currency.

  Still to come, each with its own part: the product cards above the lists,
  the Calls list, the notices about reading the chains, the lists and rows
  rereading themselves while the page is open, and every wallet press (Bid,
  Buy, Claim and Refund).
  """
  use RegentsWeb, :live_view

  import RegentsWeb.Autolaunch.Components.MarketCard,
    only: [
      auction_list: 1,
      token_list: 1,
      explore_card: 1,
      backed_card: 1,
      auction_status: 1,
      connections_for: 2,
      figure_rate: 2
    ]

  import RegentsWeb.Components.ValueCards

  import RegentsWeb.Autolaunch.Components.ChainIcon
  import RegentsWeb.Autolaunch.Components.LinkIcon
  alias Phoenix.LiveView.AsyncResult
  alias Regents.Autolaunch.{Lab, UsdRates}
  alias RegentsWeb.Autolaunch.{HomeMarket, LiveListings, PublicDocuments}

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

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page("/autolaunch"))
     |> assign(
       client_tag: Map.fetch!(session, "client_tag"),
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
       backed: :unknown,
       coming: :unknown,
       rates: AsyncResult.loading(),
       values: values(),
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

  # The "Principles" row at the foot of the page: what Autolaunch holds to, one
  # card each, drawn by the panels in assets/js/value_cards/panels/autolaunch/.
  defp values do
    [
      %{
        id: "autolaunch/clearing",
        name: "Fair price",
        headline: "One price for every bidder.",
        line: "Bids above the clearing price all pay that price, not their own limit.",
        tint: "#ff5b19",
        action: "Read rules",
        href: ~p"/autolaunch/how-it-works#how-it-works-auction"
      },
      %{
        id: "autolaunch/vault",
        name: "Locked liquidity",
        headline: "Liquidity no one can pull.",
        line: "It sits in a contract that can only collect trading fees.",
        tint: "#4fd3ec",
        action: "See fees",
        href: ~p"/autolaunch/how-it-works#how-it-works-fees"
      },
      # The stocks and portfolio pages keep their addresses under /autolaunch,
      # written out until they come (they answer 404 until then).
      %{
        id: "autolaunch/address",
        name: "Stock tokens",
        headline: "Every stock named exactly.",
        line: "Each stock shows its issuer and chain, and its exact address before you sign.",
        tint: "#00c805",
        action: "See stocks",
        href: "/autolaunch/stocks"
      },
      %{
        id: "autolaunch/signature",
        name: "Your wallet",
        headline: "Your wallet signs everything.",
        line: "Autolaunch never holds your keys or your money.",
        tint: "#e5e3d2",
        action: "See portfolio",
        href: "/autolaunch/portfolio"
      },
      %{
        id: "autolaunch/handoff",
        name: "Agents",
        headline: "Agents prepare, you sign.",
        line: "A paired agent can fill in your launch for you to check and sign.",
        tint: "#f5c16c",
        action: "Pair agent",
        href: ~p"/account/agents"
      },
      %{
        id: "autolaunch/blocks",
        name: "Onchain",
        headline: "Figures from the chain.",
        line: "Auction prices, bids and amounts raised come from the auction contracts.",
        tint: "#aecacd",
        action: "See auctions",
        href: ~p"/autolaunch/auctions"
      }
    ]
  end

  # The "Bid volume" row: up to six launches with the most put in by bidders,
  # whatever the list below shows. Launches nobody has bid on stay out of it.
  defp read_backed do
    with {:ok, auctions} <- Regents.Autolaunch.HomeMarket.auctions(%{sort: "volume"}, 6),
         do: {:ok, Enum.filter(auctions, &raised?/1)}
  end

  # "Coming next": up to three auctions taking bids, the soonest to close
  # first, then those opening soon. Not known unless both reads answer.
  defp read_coming do
    with {:ok, live} <- read_auctions(%{state: "active", sort: "ending"}),
         {:ok, opening} <- read_auctions(%{state: "created"}),
         do: {:ok, Enum.take(live ++ opening, 3)}
  end

  defp read_auctions(arguments), do: Regents.Autolaunch.HomeMarket.auctions(arguments, 3)

  defp raised?(%{bid_volume_usd: %Decimal{} = volume}), do: Decimal.gt?(volume, 0)
  defp raised?(_auction), do: false

  # A row as its read answered it: its auctions, none at all, or not known.
  defp row({:ok, auctions}), do: auctions
  defp row({:error, _reason}), do: :unknown

  # The dollar prices, read in the background (`Regents.Autolaunch.UsdRates`).
  defp read_rates(socket),
    do: assign_async(socket, :rates, fn -> {:ok, %{rates: UsdRates.rates()}} end)

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

  # A listing counts only while the page is waiting for one. A change the
  # allowance refused since the read began has already answered for the list
  # the page now names, so that read's late answer is dropped.
  def handle_async(:home_market, _answer, %{assigns: %{market_loading: false}} = socket),
    do: {:noreply, socket}

  def handle_async(:home_market, {:ok, {:ok, page}}, socket),
    do: {:noreply, put_market(socket, page)}

  def handle_async(:home_market, _failure, socket), do: {:noreply, market_failed(socket)}

  # The cards already shown stay until the new listing arrives and replaces
  # them, so changing a setting never blanks the gallery.
  defp load_market(socket, append?) do
    options = socket.assigns.market_options
    cursor = if append?, do: socket.assigns.next_cursor
    socket = assign(socket, listed: options, market_append: append?)

    case LiveListings.admit(socket) do
      :ok ->
        socket
        |> assign(market_loading: true, market_failed: false)
        |> start_async(:home_market, fn -> LiveListings.read(options, cursor) end)

      :limited ->
        market_failed(socket)
    end
  end

  # The page's first listing is read before it is shown, so the coins are in
  # the page as it arrives, for readers that run no scripts too. Later
  # listings load beside the ones already shown. The rows beside the list and
  # the dollar prices are read with it, once, under the same spend of the
  # allowance; the prices only on the live connection.
  defp first_market(socket) do
    socket = assign(socket, market_append: false, listed: socket.assigns.market_options)

    case LiveListings.admit(socket) do
      :ok ->
        socket
        |> assign(backed: row(read_backed()), coming: row(read_coming()))
        |> read_rates()
        |> read_first()

      :limited ->
        market_failed(socket)
    end
  end

  defp read_first(socket) do
    case LiveListings.read(socket.assigns.market_options, nil) do
      {:ok, page} -> put_market(socket, page)
      _failure -> market_failed(socket)
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

  attr :coming, :any, required: true, doc: "the auctions, or `:unknown` when the read failed"

  # What a visitor can join next: the auctions taking bids or opening soon.
  # While there are none, one quiet line says so; the list below keeps the
  # past ones. When the read did not answer, the row is left out.
  defp coming_next(%{coming: :unknown} = assigns), do: ~H""

  defp coming_next(assigns) do
    ~H"""
    <section class="home-next" aria-labelledby="home-next-title">
      <h2 id="home-next-title">Coming next</h2>
      <ol :if={@coming != []} id="home-next-auctions" class="home-next__row">
        <li :for={auction <- @coming} id={"home-next-card-#{auction.id}"}>
          <.link navigate={RegentsWeb.Autolaunch.Paths.auction(auction)} class="home-next__card">
            <strong>{auction.title}</strong>
            <small>{auction.token_symbol}</small>
            <.auction_status id={"home-next-#{auction.id}"} auction={auction} />
          </.link>
        </li>
      </ol>
      <div :if={@coming == []} class="home-next__empty">
        <Regent.Icons.icon name="clock" class="home-next__mark" />
        <p><strong>No auction is taking bids</strong></p>
      </div>
    </section>
    """
  end

  attr :backed, :any, required: true, doc: "the auctions, or `:unknown` when the read failed"

  # The "Bid volume" row, shown only once someone has bid on a launch.
  defp bid_volume(%{backed: [_ | _]} = assigns) do
    ~H"""
    <section class="home-backed" aria-labelledby="home-backed-title">
      <h2 id="home-backed-title">Bid volume</h2>
      <ol class="home-backed__row">
        <li :for={{auction, rank} <- Enum.with_index(@backed, 1)}>
          <.backed_card auction={auction} rank={rank} />
        </li>
      </ol>
    </section>
    """
  end

  defp bid_volume(assigns), do: ~H""

  # The gallery's first picture loads first unless Bid volume draws its own
  # first picture.
  defp lead?(0, [_ | _]), do: false
  defp lead?(0, _backed), do: true
  defp lead?(_index, _backed), do: false

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
            lead={lead?(index, @backed)}
            creator_connections={connections_for(record, @creators)}
            rate={
              figure_rate(@rates, if(@records_kind == :auction, do: record, else: record.auction))
            }
          />
        </div>
        <.auction_list
          :if={
            @market_options.display == "list" && @kind == :auction &&
              (@records != [] || @market_loading)
          }
          creators={@creators}
          records={if @records_kind == :auction, do: @records, else: []}
          rates={@rates}
          loading={@market_loading}
        />
        <.token_list
          :if={
            @market_options.display == "list" && @kind == :token &&
              (@records != [] || @market_loading)
          }
          creators={@creators}
          records={if @records_kind == :token, do: @records, else: []}
          rates={@rates}
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

      <.coming_next coming={@coming} />

      <.bid_volume backed={@backed} />

      <section class="home-values" aria-labelledby="home-values-title">
        <h2 id="home-values-title">Principles</h2>
        <.value_cards id="cards-row" label="Principles" cards={@values} />
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
