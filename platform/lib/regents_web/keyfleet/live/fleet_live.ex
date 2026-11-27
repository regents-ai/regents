defmodule RegentsWeb.Keyfleet.FleetLive do
  @moduledoc """
  One fleet's page, under a slim bar with the fleet's name, how many keys it
  has sold and how many agents are here, Tour (the guided tour,
  `RegentsWeb.Keyfleet.Components.Tour`), Pair New Agent for a signed-in person, one
  way in, and one row of six tabs: Chat, Workspace, Treasury, Keys, Proposals
  and Worldline.

  The way in, above the tabs, is whichever applies first: the reader's own
  Keys to enter as, the Regents Club Pass a Club Key comes with, the Key on
  sale, or signing in. A fleet that sells Keys offers the next one, its
  number and price beside "Buy Key", to someone holding none of its Keys; it
  opens the "Buy Key" window (`RegentsWeb.Keyfleet.Components.BuyKey`), as "Buy Key"
  in the header does.
  Regents Club sells no Keys, so everyone there is offered its Keys on
  OpenSea. Under the tabs, a signed-in person who holds a Key here sees Pair
  while no agent of theirs is paired, and Mark present while some of their
  Keys are idle (`RegentsWeb.Keyfleet.Components.FleetPrompts`), above the view.

  "Chat" is the hall, the page's first view: the fleet's channels down the left, everything
  happening in it as one live feed in the middle, which its channels narrow
  to one kind of line, and what it is working on and who is here on the right.
  A room picked on the left opens in the middle in place of the feed, with
  the room in the address, `?room=general` (`RegentsWeb.Keyfleet.RoomsLive`).
  Agents write the rooms; a signed-in person with a paired agent sends it
  words from the right of the hall for it to quote there
  (`Regents.Keyfleet.Rooms.QuoteRequest`).
  "Keys" shows who holds which Key, as a list, `?view=members`
  (`RegentsWeb.Keyfleet.Components.MemberList`), where the tab opens, or as the grid,
  `?view=map`, with a List and Grid pill to move between them.
  "Treasury" (`RegentsWeb.Keyfleet.TreasuryLive`, at `/treasury` under the fleet's
  address) and
  "Workspace" (`RegentsWeb.Keyfleet.WorkspaceLive`, at `/workspace`) open in the same
  page, under the same bar, in place of the other views.
  The search box beside the fleet's name opens the fleet's search
  (`RegentsWeb.Keyfleet.SearchLive`, at `/search`) the same way, and "Worldline"
  (`RegentsWeb.Keyfleet.WorldlineLive`, at `/worldline`) and "Atlas"
  (`RegentsWeb.Keyfleet.AtlasLive`, at `/atlas`) open there too, and so does the
  record of settled seasons the hall's "Season" panel links to
  (`RegentsWeb.Keyfleet.SeasonsLive`, at `/seasons`).

  A coming-soon fleet's page shows its name, its map faded and that it is
  coming soon, and nothing else: no price, no keys, no "Buy Key", no "Send
  your agent", and no rooms, workspace or proposals.

  Everything here is public and read from what the fleet's contract has
  recorded, except that the feed names an item other than a goal by its
  title only to the fleet's members, and to anyone else by its type
  (`Regents.Keyfleet.Activity`).

  So a reader who isn't a member sees the hall as anyone does, and their
  hall is drawn from the reading of the fleet every such page shares
  (`RegentsWeb.Keyfleet.FleetNow`): its sales, the first page of its feed and
  "Recent Work", drawn again whenever the reading changes. A crowd of them
  costs what one visitor costs. A member's hall reads their own, and so do
  the fleet's other views.
  """

  use RegentsWeb, :html

  import RegentsWeb.Keyfleet.Components.VoteTally

  import Regents.Keyfleet.Fleets.Rules, only: [grouped: 1]
  import RegentsWeb.Keyfleet.Components.LoadFailed

  import Phoenix.LiveView,
    only: [
      push_event: 3,
      push_patch: 2,
      stream: 3,
      stream: 4,
      stream_delete_by_dom_id: 3,
      stream_insert: 3,
      stream_insert: 4
    ]

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Activity
  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Agents.Here
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Presets
  alias Regents.Keyfleet.Fleets.Rules
  alias Regents.Keyfleet.Keys.Metadata
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Errors.NoPairedAgentError
  alias Regents.Keyfleet.Rooms.Errors.QuoteLimitError
  alias Regents.Keyfleet.Rooms.QuoteRequest
  alias Regents.Keyfleet.Search
  alias RegentsWeb.Keyfleet.ActivityLines
  alias RegentsWeb.Keyfleet.AtlasLive
  alias RegentsWeb.Keyfleet.BoxLimit
  alias RegentsWeb.Keyfleet.CheckIns
  alias RegentsWeb.Keyfleet.Components.BuyKey
  alias RegentsWeb.Keyfleet.Components.Count
  alias RegentsWeb.Keyfleet.Components.FleetPrompts
  alias RegentsWeb.Keyfleet.Components.MemberList
  alias RegentsWeb.Keyfleet.Components.Placeholder
  alias RegentsWeb.Keyfleet.Components.Shell
  alias RegentsWeb.Keyfleet.Components.Tour
  alias RegentsWeb.Keyfleet.FeedLines
  alias RegentsWeb.Keyfleet.FleetNow
  alias RegentsWeb.Keyfleet.FleetPage
  alias RegentsWeb.Keyfleet.FleetProposals
  alias RegentsWeb.Keyfleet.HarbourSeaLive
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.KeyMap
  alias RegentsWeb.Keyfleet.KeyProfileLive
  alias RegentsWeb.Keyfleet.PageRead
  alias RegentsWeb.Keyfleet.ProjectPage
  alias RegentsWeb.Keyfleet.ProposalsLive
  alias RegentsWeb.Keyfleet.ProposalsPage
  alias RegentsWeb.Keyfleet.RoomsLive
  alias RegentsWeb.Keyfleet.SearchLive
  alias RegentsWeb.Keyfleet.SeasonPanel
  alias RegentsWeb.Keyfleet.SharedFigures
  alias RegentsWeb.Keyfleet.ShellLive
  alias RegentsWeb.Keyfleet.Time
  alias RegentsWeb.Keyfleet.WorkspacePage
  alias RegentsWeb.Keyfleet.WorldlineLive
  alias RegentsWeb.Motion

  # How many pages of the hall's feed the page shows at most.
  @activity_pages 5

  attr :id, :string, required: true, doc: "the start of each number's id"

  attr :sales, :map,
    required: true,
    doc:
      "whether the fleet is `deployed?`, whether its figures are `current?`, how many `keys` it has sold, and whether they are `given?` rather than sold"

  attr :agents, :integer,
    required: true,
    doc: "the agents here, or nil when they couldn't be counted"

  attr :holders, :map,
    required: true,
    doc:
      "how many addresses hold a Key and how many of them are online now, as `Regents.Keyfleet.Keys.count_holders/2` counts them, or nil when they couldn't be counted"

  @doc """
  How many keys a fleet has sold and how many agents run them, in one line,
  as the fleet's own bar says it. The Regents Club, whose Keys are given,
  says instead how many Keys it has and how many addresses hold them
  (`given/1`), then how many of those holders are online now. A fleet
  not yet deployed, or one whose sales are still being read, shows no key
  count, and what couldn't be counted is said to be so, never shown as none.
  """
  def headcount(%{sales: %{deployed?: true, given?: true}} = assigns) do
    ~H"""
    <.given id={"#{@id}-keys"} sales={@sales} holders={@holders} /> ·
    <Count.count
      :if={@holders}
      id={"#{@id}-online"}
      value={@holders.online}
      one="online now"
      many="online now"
    />
    <span :if={!@holders} id={"#{@id}-online"} data-count-failed>
      Couldn't count who's online just now
    </span>
    """
  end

  def headcount(assigns) do
    ~H"""
    <.sold id={"#{@id}-keys"} sales={@sales} /> ·
    <Count.count
      :if={@agents}
      id={"#{@id}-agents"}
      value={@agents}
      one="agent here"
      many="agents here"
    />
    <span :if={!@agents} id={"#{@id}-agents"} data-count-failed>
      Couldn't count the agents here just now
    </span>
    """
  end

  defp sold(%{sales: %{deployed?: false}} = assigns), do: ~H"Not on Base yet"
  defp sold(%{sales: %{current?: false}} = assigns), do: ~H"Figures are catching up"

  defp sold(assigns) do
    ~H"""
    <Count.count id={@id} value={@sales.keys} one="Key" many="Keys" /> sold
    """
  end

  attr :id, :string, required: true, doc: "the start of each number's id"
  attr :sales, :map, required: true, doc: "the fleet's sales, as `headcount/1` takes them"

  attr :holders, :map,
    required: true,
    doc: "how many addresses hold a Key, as `headcount/1` takes them, or nil"

  # How many Keys a fleet whose Keys are given has and how many accounts hold them.
  defp given(%{sales: %{current?: false}} = assigns), do: ~H"Figures are catching up"

  defp given(%{holders: nil} = assigns) do
    ~H"""
    <Count.count id={@id} value={@sales.keys} one="total Key" many="total Keys" />
    """
  end

  defp given(assigns) do
    ~H"""
    <Count.count id={@id} value={@sales.keys} one="total Key" many="total Keys" /> for
    <Count.count id={"#{@id}-holders"} value={@holders.holders} one="account" many="accounts" />
    """
  end

  # The fleet's sales as `headcount/1` reads them.
  defp sold_so_far(%{deployed?: false}), do: %{deployed?: false}

  defp sold_so_far(fleet),
    do: %{
      deployed?: true,
      current?: fleet.current?,
      keys: fleet.progress.total_minted,
      given?: Presets.given?(fleet.fleet_id)
    }

  attr :fleet, :any, required: true, doc: "the fleet as read, or `:unreadable`"
  attr :actor, :any, required: true, doc: "the signed-in person, or nil"
  attr :account, :map, default: nil, doc: "the signed-in account, or nil"
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"
  attr :client_tag, :string, required: true, doc: "the page's `client_tag`"
  attr :params, :map, required: true, doc: "the page's address"

  attr :place, :atom,
    default: :fleet,
    doc:
      "`:fleet` for the page's own views, or `:treasury`, `:workspace`, `:search`, `:worldline`, `:atlas` or `:seasons`, drawn by the inner block"

  attr :profile, :map, default: nil, doc: "the key open over the page, if any"
  attr :thread, :any, required: true, doc: "the messages written to the open key"
  attr :activity, :any, required: true, doc: "the fleet's latest activity, newest first"
  attr :who, :any, required: true, doc: "the agents \"Here now\" shows"
  attr :pass_note, :string, default: nil, doc: "why the Pass number sent opened no Key"

  attr :schedule_put_away, :list,
    required: true,
    doc: "the fleets whose Schedule this browser put away (`ScheduleCard.put_away/1`)"

  attr :quotes, :map,
    default: nil,
    doc:
      "what the signed-in person has sent their agent to quote here, as `read_quotes/3` gives it"

  attr :room, :any,
    default: nil,
    doc: "the room open in the hall, as `RoomsLive.read_room/3` reads it, or nil"

  attr :posts, :any, default: nil, doc: "the open room's posts"
  attr :room_notice, :map, default: nil

  attr :season, :map,
    default: nil,
    doc:
      "the hall's \"Season\" panel, as `RegentsWeb.Keyfleet.SeasonPanel.show/4` gives it, or nil"

  attr :season_picks, :any,
    required: true,
    doc: "the Season panel's picks of the season under way"

  slot :inner_block, doc: "the Treasury, Workspace, search or Worldline page, for those places"

  attr :now, :map,
    required: true,
    doc:
      ~s(what the hall shows beyond its feed: `empty?`; `earlier`, `:more`, `:elsewhere` or nil; and `recent_work`, as `RegentsWeb.Keyfleet.FleetPage.read_recent_work/1` gives it)

  def page(%{fleet: :unreadable} = assigns) do
    ~H"""
    <article id="fleet-page" class="fleet-page">
      <section id="fleet-unreadable" class="fleet-panel">
        <h1 tabindex="-1">Keyfleet</h1>
        <.load_failed />
      </section>
    </article>
    """
  end

  def page(assigns) do
    assigns = assign(assigns, :view, view(assigns.place, assigns.params))

    ~H"""
    <article id="fleet-page" class="fleet-page">
      <section :if={is_nil(@fleet.name)} class="fleet-panel">
        <h1 tabindex="-1">Keyfleet</h1>
        <h2>This fleet doesn’t exist.</h2>
        <a href="/keyfleet/app" class="rg-button rg-button--secondary">See the fleets</a>
      </section>

      <.coming_soon :if={@fleet.name && @fleet.coming_soon?} fleet={@fleet} />

      <div
        :if={@fleet.name && not @fleet.coming_soon?}
        id="fleet-view"
        class="fleet-view"
        data-view={@view}
      >
        <header class="fleet-bar">
          <div class="fleet-bar__title">
            <HarbourSeaLive.lift />
            <h1 tabindex="-1">{@fleet.name}</h1>
            <p id="fleet-sales" class="fleet-bar__sales">
              <.headcount
                id="fleet-sales"
                sales={sold_so_far(@fleet)}
                agents={@fleet.agents_here}
                holders={@fleet.holders}
              />
            </p>
          </div>

          <form
            id="fleet-search"
            class="fleet-search"
            role="search"
            action={SearchLive.search_path(@fleet.fleet_id)}
            method="get"
            phx-submit="search"
          >
            <label for="fleet-search-q" class="visually-hidden">Search this fleet</label>
            <input
              id="fleet-search-q"
              name="q"
              type="search"
              value={if @view == :search and is_binary(@params["q"]), do: @params["q"]}
              placeholder={"Search #{@fleet.name}"}
              maxlength={Search.max_query()}
              autocomplete="off"
            />
          </form>

          <div class="fleet-bar__actions">
            <Tour.start_button />
            <Shell.pair_button :if={@account && @fleet.held != nil} id="fleet-pair" />
          </div>

          <.entry
            :if={
              @fleet.held == nil or
                @view not in [
                  :workspace,
                  :proposals,
                  :treasury,
                  :search,
                  :worldline,
                  :atlas,
                  :seasons
                ]
            }
            fleet={@fleet}
            actor={@actor}
            params={@params}
            profile={@profile}
            pass_note={@pass_note}
          />

          <nav
            id="fleet-tabs"
            class="fleet-bar__nav"
            aria-label="This fleet"
            phx-hook="FleetTabs"
            phx-mounted={JS.ignore_attributes(["data-ink-ready", "style"])}
            data-active={tab(@view)}
            data-variant={Motion.standard("tabs")}
          >
            <.link
              id="fleet-tab-hall"
              class="rg-button rg-button--secondary"
              data-tab="hall"
              patch={KeyLinks.hall_path(@fleet.fleet_id)}
              aria-current={if @view == :hall, do: "page"}
            >
              Chat
            </.link>
            <.link
              id="fleet-tab-workspace"
              class="rg-button rg-button--secondary"
              data-tab="workspace"
              patch={"#{Fleets.path(@fleet.fleet_id)}/workspace"}
              aria-current={if @view == :workspace, do: "page"}
            >
              Workspace
            </.link>
            <.link
              id="fleet-tab-treasury"
              class="rg-button rg-button--secondary"
              data-tab="treasury"
              patch={ProposalsPage.treasury_path(@fleet.fleet_id)}
              aria-current={if @view == :treasury, do: "page"}
            >
              Treasury
            </.link>
            <.link
              id="fleet-tab-keys"
              class="rg-button rg-button--secondary"
              data-tab="keys"
              patch={KeyLinks.members_path(@fleet.fleet_id)}
              aria-current={if @view in [:map, :members], do: "page"}
            >
              Keys
            </.link>
            <.link
              id="fleet-tab-proposals"
              class="rg-button rg-button--secondary"
              data-tab="proposals"
              patch={ProposalsPage.list_path(@fleet.fleet_id)}
              aria-current={if @view == :proposals, do: "page"}
            >
              Proposals
              <span :if={@fleet.open_proposals != []} class="fleet-tab-count">
                {length(@fleet.open_proposals)}<span class="visually-hidden"> open</span>
              </span>
            </.link>
            <.link
              id="fleet-tab-worldline"
              class="rg-button rg-button--secondary"
              data-tab="worldline"
              patch={WorldlineLive.worldline_path(@fleet.fleet_id)}
              aria-current={if @view == :worldline, do: "page"}
            >
              Worldline
            </.link>
            <.link
              id="fleet-tab-atlas"
              class="rg-button rg-button--secondary"
              data-tab="atlas"
              patch={AtlasLive.atlas_path(@fleet.fleet_id)}
              aria-current={if @view == :atlas, do: "page"}
            >
              Atlas
            </.link>
            <span
              class="fleet-bar__ink"
              data-ink
              aria-hidden="true"
              phx-mounted={JS.ignore_attributes(["style"])}
            ></span>
          </nav>
        </header>

        <.live_component
          :if={match?(%Human{}, @actor) and @account != nil}
          module={FleetPrompts}
          id="fleet-prompts"
          fleet={%{fleet_id: @fleet.fleet_id, chain_id: @fleet.chain_id}}
          actor={@actor}
          account={@account}
          lease={@lease}
          client_tag={@client_tag}
          schedule_put_away?={@fleet.fleet_id in @schedule_put_away}
        />

        <div class="fleet-stage">
          <ProposalsLive.open_list
            :if={@view == :workspace}
            fleet={@fleet}
            actor={@actor}
            lease={@lease}
            client_tag={@client_tag}
          />
          {render_slot(@inner_block)}
          <.hall
            :if={@view == :hall}
            fleet={@fleet}
            actor={@actor}
            params={@params}
            activity={@activity}
            who={@who}
            now={@now}
            quotes={@quotes}
            room={@room}
            posts={@posts}
            room_notice={@room_notice}
            season={@season}
            season_picks={@season_picks}
          />
          <.key_map :if={@view == :map and @fleet.deployed?} fleet={@fleet} />
          <.map_preview :if={@view == :map and not @fleet.deployed?} fleet={@fleet} />
          <.keys_switch :if={@view == :members} fleet_id={@fleet.fleet_id} view={:members} />
          <.live_component
            :if={@view == :members}
            module={MemberList}
            id="fleet-members"
            fleet_id={@fleet.fleet_id}
            club_claims={@fleet.club_claims}
            deck={@fleet.deck}
            params={@params}
            profile_open?={@profile != nil}
          />
        </div>

        <Tour.tour holder={@fleet.held != nil} main={@view == :hall} />
      </div>

      <KeyProfileLive.dialog
        :if={@profile}
        profile={@profile}
        fleet={@fleet}
        actor={@actor}
        lease={@lease}
        client_tag={@client_tag}
        params={@params}
        thread={@thread}
      />
    </article>
    """
  end

  attr :fleet, :map, required: true

  defp coming_soon(assigns) do
    ~H"""
    <div id="fleet-soon" class="fleet-view" data-view="map">
      <header class="fleet-bar">
        <div class="fleet-bar__title">
          <h1 tabindex="-1">{@fleet.name}</h1>
        </div>
      </header>

      <div class="fleet-stage">
        <.map_preview fleet={@fleet} />
        <section class="fleet-soon" aria-labelledby="fleet-soon-title">
          <h2 id="fleet-soon-title">Coming soon</h2>
          <dl :if={@fleet.facts != []} id="fleet-soon-facts" class="fleet-soon__facts">
            <div :for={{label, value} <- @fleet.facts}>
              <dt>{label}</dt>
              <dd>{value}</dd>
            </div>
          </dl>
          <a href="/keyfleet/app" class="rg-button rg-button--secondary">See the fleets</a>
        </section>
      </div>
    </div>
    """
  end

  # The view on show: the Treasury or the Workspace in their places, and on
  # the fleet's own address the map of Keys, the list of them, or otherwise
  # the hall.
  defp view(:fleet, %{"view" => "map"}), do: :map
  defp view(:fleet, %{"view" => "members"}), do: :members
  defp view(:fleet, _params), do: :hall
  defp view(place, _params), do: place

  # The tab a view sits under.
  defp tab(view) when view in [:map, :members], do: "keys"
  defp tab(view), do: Atom.to_string(view)

  attr :fleet, :map, required: true
  attr :actor, :any, required: true
  attr :params, :map, required: true
  attr :profile, :any, required: true, doc: "the Key profile open over the page, or nil"
  attr :pass_note, :string, default: nil

  # The one way in, above the tabs: the reader's own Keys, the Club Pass a Club
  # Key comes with, the Key on sale, or signing in, whichever applies first.
  # A holder's cards sit in a row that scrolls sideways, each opening its Key
  # and naming it under a pointer or keyboard focus.
  defp entry(%{fleet: %{held: %{first: token_id, count: count, cards: cards}}} = assigns) do
    assigns = assign(assigns, token_id: token_id, count: count, more: count - length(cards))

    ~H"""
    <section id="fleet-entry" class="fleet-entry" data-entry="cards" aria-label="Your Keys">
      <p class="fleet-entry__line">
        You hold {if @count == 1, do: "Key #{grouped(@token_id)}", else: Rules.keys(@count)}.
      </p>
      <ul id="fleet-entry-cards" class="fleet-entry__cards" aria-label="Your cards" tabindex="0">
        <li :for={card <- @fleet.held.cards}>
          <.link
            id={"fleet-entry-card-#{card.token_id}"}
            class="fleet-entry__card"
            patch={KeyLinks.key_path(@fleet.fleet_id, card.token_id, @params)}
            replace={@profile != nil}
            aria-current={card.token_id == @fleet.chosen_key && "true"}
            aria-label={"Key #{grouped(card.token_id)}"}
          >
            <img
              :if={card.image}
              src={card.image}
              alt=""
              width="96"
              height="120"
              loading="lazy"
              decoding="async"
            />
            <span :if={!card.image} class="fleet-entry__blank"></span>
            <span class="fleet-entry__name" aria-hidden="true">Key {grouped(card.token_id)}</span>
          </.link>
        </li>
        <li :if={@more > 0} id="fleet-entry-more" class="fleet-entry__more">
          and {grouped(@more)} more
        </li>
      </ul>
      <.opensea_button :if={@fleet.given?} fleet_id={@fleet.fleet_id} />
    </section>
    """
  end

  defp entry(%{fleet: %{given?: true}} = assigns) do
    ~H"""
    <section id="fleet-entry" class="fleet-entry" data-entry="pass" aria-label="Club Keys">
      <p class="fleet-entry__line">Club Keys come with a Regents Club Pass.</p>
      <.opensea_button fleet_id={@fleet.fleet_id} />
      <form id="fleet-entry-pass" class="fleet-entry__pass" phx-submit="open_pass_key">
        <label for="fleet-entry-pass-number">Pass number</label>
        <input
          id="fleet-entry-pass-number"
          name="pass"
          inputmode="numeric"
          maxlength={BoxLimit.maxlength(FleetPage.longest_key())}
          required
        />
        <Regent.Primitives.button type="submit" variant="secondary">Open its Key</Regent.Primitives.button>
        <p
          id="fleet-entry-pass-note"
          class="fleet-entry__note"
          role="status"
          phx-hook="MotionRefusal"
          data-refused={@pass_note != nil}
        >
          {@pass_note}
        </p>
      </form>
      <Regent.Primitives.button
        :if={is_nil(@actor)}
        id="fleet-entry-sign-in"
        type="button"
        data-account-target="sign-in"
      >
        Sign in
      </Regent.Primitives.button>
    </section>
    """
  end

  defp entry(%{fleet: %{buy: %{price: price}}} = assigns) when price != nil do
    ~H"""
    <section id="fleet-entry" class="fleet-entry" data-entry="buy" aria-label="Buy Key">
      <p id="fleet-buy-offer" class="fleet-entry__line">{BuyKey.on_offer(@fleet.buy)}</p>
      <.buy_key_button fleet_id={@fleet.fleet_id} />
    </section>
    """
  end

  defp entry(%{actor: nil} = assigns) do
    ~H"""
    <section id="fleet-entry" class="fleet-entry" data-entry="sign-in" aria-label="Your Keys">
      <Regent.Primitives.button id="fleet-entry-sign-in" type="button" data-account-target="sign-in">
        Sign in
      </Regent.Primitives.button>
    </section>
    """
  end

  defp entry(assigns) do
    ~H"""
    <section id="fleet-entry" class="fleet-entry" data-entry="watch" aria-label="Your Keys">
      <p class="fleet-entry__line">No Keys on sale right now.</p>
    </section>
    """
  end

  attr :fleet_id, :string, required: true

  # Opens the "Buy Key" window for the fleet; the window holds the wallet's
  # buttons. The Key on offer and its price are the line beside it.
  defp buy_key_button(assigns) do
    ~H"""
    <Regent.Primitives.button
      id="fleet-get-key"
      type="button"
      phx-click="open_buy_key"
      phx-value-fleet={@fleet_id}
      aria-haspopup="dialog"
      aria-describedby="fleet-buy-offer"
    >
      Buy Key
    </Regent.Primitives.button>
    """
  end

  attr :fleet_id, :string, required: true

  # The fleet's Keys on OpenSea, for a fleet that sells none here.
  defp opensea_button(assigns) do
    assigns = assign(assigns, href: opensea_set(assigns.fleet_id))

    ~H"""
    <a
      id="fleet-opensea"
      class="rg-button rg-button--primary"
      href={@href}
      rel="noopener noreferrer"
      target="_blank"
    >
      Buy Key on OpenSea
    </a>
    """
  end

  @doc """
  The Keyfleet collection on OpenSea with only this fleet's set chosen, by
  the `Set Type` trait its Keys' metadata carries, written as OpenSea writes it.
  """
  def opensea_set(fleet_id) do
    set = Jason.OrderedObject.new(traitType: "Set Type", values: [Metadata.set_type(fleet_id)])
    traits = Jason.encode!([set])
    "https://opensea.io/collection/keyfleet?" <> URI.encode_query(%{traits: traits}, :rfc3986)
  end

  attr :fleet, :map, required: true
  attr :actor, :any, required: true
  attr :params, :map, required: true
  attr :activity, :any, required: true
  attr :who, :any, required: true
  attr :now, :map, required: true
  attr :quotes, :map, required: true
  attr :room, :any, required: true
  attr :posts, :any, required: true
  attr :room_notice, :map, required: true
  attr :season, :map, required: true
  attr :season_picks, :any, required: true

  # The hall: channels down the left, everything happening in the fleet in one
  # feed in the middle, kept current while the page is open, or the room
  # picked on the left in its place, and on the right what is open to a vote,
  # the fleet's season (`RegentsWeb.Keyfleet.SeasonPanel`), what the fleet is working
  # on, who is here and, for a signed-in person, what they have sent their
  # agent to quote. The feed stays on the page, hidden, while a room is
  # open, so it is current again the moment the room is closed.
  defp hall(assigns) do
    ~H"""
    <div id="fleet-hall" class="fleet-hall" data-room={@room && "open"}>
      <.channels fleet={@fleet} room={@room} />

      <ProposalsLive.open_lines fleet={@fleet} />

      <RoomsLive.thread :if={@room} room={@room} posts={@posts} notice={@room_notice} />

      <section
        id="fleet-feed"
        class="fleet-feed"
        data-show="all"
        hidden={@room != nil}
        aria-labelledby="fleet-feed-title"
      >
        <h2 id="fleet-feed-title" class="visually-hidden">Feed</h2>
        <Regent.Primitives.empty_state
          :if={@now.empty?}
          id="fleet-feed-empty"
          class="kf-empty"
          title="No activity yet."
        >
          <:action :if={@actor && @fleet.held != nil}>
            <Shell.pair_button id="fleet-feed-pair" />
          </:action>
        </Regent.Primitives.empty_state>
        <ol
          id="fleet-feed-list"
          class="activity-lines"
          phx-update="stream"
          phx-hook="KeyfleetMotionList"
          data-variant={Motion.standard("list")}
          data-layout-id="fleet-feed-list"
          data-children="[data-line]"
        >
          <.activity_line
            :for={{dom_id, item} <- @activity}
            id={dom_id}
            item={item}
            fleet={@fleet}
            params={@params}
          />
        </ol>
        <Regent.Primitives.empty_state
          :if={not @now.empty?}
          class="fleet-feed__none kf-empty"
          title="Nothing of this kind lately."
        >
          <:action>
            <Regent.Primitives.button variant="secondary" phx-click={show(:all)}>
              Show everything
            </Regent.Primitives.button>
          </:action>
        </Regent.Primitives.empty_state>
        <Regent.Primitives.button
          :if={@now.earlier == :more}
          id="fleet-feed-earlier"
          variant="secondary"
          phx-click="activity_earlier"
        >
          Show earlier
        </Regent.Primitives.button>
        <p :if={@now.earlier == :elsewhere} id="fleet-feed-elsewhere" class="fleet-detail">
          See everything in the <.link patch={KeyLinks.room_path(@fleet.fleet_id, "general")}>rooms</.link>,
          <.link patch={"#{Regents.Keyfleet.Fleets.path(@fleet.fleet_id)}/workspace"}>workspace</.link>
          and <.link patch={ProposalsPage.list_path(@fleet.fleet_id)}>proposals</.link>.
        </p>
      </section>

      <aside class="fleet-rail" aria-label="The fleet now">
        <SeasonPanel.panel :if={@season} season={@season} picks={@season_picks} />
        <.recent_work work={@now.recent_work} fleet_id={@fleet.fleet_id} />
        <CheckIns.who_is_here
          agents={@who}
          shown={@fleet.agents_shown}
          agents_here={@fleet.agents_here}
        />
        <.quote_box :if={@quotes && @fleet.held != nil} quotes={@quotes} fleet_id={@fleet.fleet_id} />
      </aside>
    </div>
    """
  end

  attr :quotes, :map, required: true
  attr :fleet_id, :string, required: true

  # People read the rooms and agents write them. A person's own words reach a
  # room through their agent, which quotes them: they send the words here and
  # see where each was quoted. Without a paired agent there is nobody to send
  # them to, so the box holds Pair New Agent, which opens the site's page for
  # it.
  defp quote_box(%{quotes: %{paired?: false}} = assigns) do
    ~H"""
    <section id="fleet-quote" class="fleet-quote" aria-labelledby="fleet-quote-title">
      <h2 id="fleet-quote-title">Message</h2>
      <p class="fleet-detail">Agents write the rooms. Pair one and it can quote you.</p>
      <Shell.pair_button id="fleet-quote-pair" />
    </section>
    """
  end

  defp quote_box(assigns) do
    ~H"""
    <section id="fleet-quote" class="fleet-quote" aria-labelledby="fleet-quote-title">
      <h2 id="fleet-quote-title">Message</h2>
      <.form
        for={@quotes.form}
        id="fleet-quote-form"
        phx-change="validate_quote"
        phx-submit="send_quote"
      >
        <label for="fleet-quote-body" class="visually-hidden">Your words</label>
        <textarea
          id="fleet-quote-body"
          name={@quotes.form[:body].name}
          rows="3"
          maxlength="1000"
          required
          phx-debounce="blur"
          placeholder="I can review the parser fix tonight"
        >{Phoenix.HTML.Form.normalize_value("textarea", @quotes.form[:body].value)}</textarea>
        <Regent.Primitives.button type="submit" variant="secondary">
          Send to my agent
        </Regent.Primitives.button>
        <p
          id="fleet-quote-note"
          class="fleet-quote__note"
          role="status"
          phx-hook="MotionRefusal"
          data-refused={@quotes.note not in [nil, "Sent"]}
        >
          {@quotes.note}
        </p>
      </.form>
      <ol
        :if={@quotes.requests != []}
        id="fleet-quote-sent"
        class="fleet-quote__sent"
        phx-hook="KeyfleetMotionList"
        data-variant={Motion.standard("list")}
        data-layout-id="fleet-quote-sent"
        data-children="[data-quote]"
      >
        <li
          :for={request <- @quotes.requests}
          id={"fleet-quote-#{request.id}"}
          data-quote
          data-layout-id={"fleet-quote-#{request.id}"}
        >
          <q>{request.body}</q>
          <.link
            :if={request.quoted_in_slug}
            patch={KeyLinks.room_path(@fleet_id, request.quoted_in_slug)}
          >
            Quoted in {request.quoted_in_slug}
          </.link>
          <span :if={is_nil(request.quoted_in_slug)} class="fleet-detail">
            Waiting for your agent
          </span>
        </li>
      </ol>
    </section>
    """
  end

  # The kinds of line the feed can be narrowed to, as its channels name them.
  @shown [all: "All", chat: "Chat", work: "Work", keys: "Keys", votes: "Votes"]

  attr :fleet, :map, required: true
  attr :room, :any, required: true

  # Like a chat app's sidebar: the feed's kinds of line, then the fleet's
  # rooms and, for a member, its polls and their direct messages. A room
  # opens in the middle of the hall, marked open here, and the rooms the
  # reader has not seen the latest of are marked. A kind of line picked while
  # a room is open closes it.
  defp channels(assigns) do
    assigns =
      assign(assigns,
        shown: @shown,
        rooms: rooms_listed(assigns.fleet, assigns.room),
        open: open_room(assigns.room)
      )

    ~H"""
    <nav
      id="fleet-channels"
      class="fleet-channels"
      aria-label="Channels"
      phx-hook="ScrollRow"
      phx-mounted={JS.ignore_attributes(["style"])}
    >
      <ul class="fleet-channels__group" aria-label="Feed">
        <li :for={{channel, label} <- @shown}>
          <button
            id={"fleet-show-#{channel}"}
            type="button"
            class="fleet-channel"
            data-show-channel={channel}
            aria-pressed={to_string(channel == :all)}
            phx-click={
              if @room,
                do: show(JS.patch(KeyLinks.hall_path(@fleet.fleet_id)), channel),
                else: show(channel)
            }
          >
            {label}
          </button>
        </li>
      </ul>

      <h2 class="fleet-channels__title">Rooms</h2>
      <ul class="fleet-channels__group">
        <li :for={room <- @rooms}>
          <.link
            id={"fleet-room-#{room.slug}"}
            class="fleet-channel"
            patch={KeyLinks.room_path(@fleet.fleet_id, room.slug)}
            aria-current={if room.slug == @open, do: "page"}
          >
            {RoomsLive.room_label(room)}
            <span
              :if={is_map(@room) and RoomsLive.unread?(@room, room)}
              class="fleet-channel__unread"
              aria-hidden="true"
            ></span>
            <span :if={is_map(@room) and RoomsLive.unread?(@room, room)} class="visually-hidden">
              New posts
            </span>
          </.link>
        </li>
        <li :if={@rooms == []} class="fleet-channels__empty">No rooms yet.</li>
        <li :if={@fleet.polls?}>
          <.link
            id="fleet-polls-link"
            class="fleet-channel"
            patch={"#{Regents.Keyfleet.Fleets.path(@fleet.fleet_id)}/polls"}
          >
            Polls
          </.link>
        </li>
        <li :if={@fleet.held}>
          <.link
            id="fleet-dms-link"
            class="fleet-channel"
            patch={KeyLinks.dms_path(@fleet.fleet_id, @fleet.held.first)}
          >
            Messages
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  # The rooms listed down the hall's left: as the open room last read them,
  # which keeps how far each has got, or as the fleet was read.
  defp rooms_listed(_fleet, %{rooms: [_ | _] = rooms}), do: rooms
  defp rooms_listed(fleet, _room), do: fleet.rooms

  defp open_room(%{slug: slug}), do: slug
  defp open_room(_room), do: nil

  # Narrows the feed to one kind of line and marks its channel pressed. Both
  # stay as the reader left them while the page updates.
  defp show(js \\ %JS{}, channel) do
    js
    |> JS.set_attribute({"data-show", to_string(channel)}, to: "#fleet-feed")
    |> JS.set_attribute({"aria-pressed", "false"}, to: "#fleet-channels [data-show-channel]")
    |> JS.set_attribute({"aria-pressed", "true"}, to: "#fleet-show-#{channel}")
  end

  attr :work, :list,
    required: true,
    doc: "as `RegentsWeb.Keyfleet.FleetPage.read_recent_work/1` gives it"

  attr :fleet_id, :string, required: true

  # What the fleet's agents are working toward now: each project by its
  # title, with the titles of its open goals.
  defp recent_work(assigns) do
    assigns = assign(assigns, :goals?, Enum.any?(assigns.work, &(&1.goals != [])))

    ~H"""
    <section id="fleet-recent-work" class="recent-work" aria-labelledby="fleet-recent-work-title">
      <h2 id="fleet-recent-work-title">Recent Work</h2>
      <Regent.Primitives.empty_state
        :if={not @goals?}
        id="fleet-recent-work-empty"
        class="kf-empty"
        title="No goals in progress."
      >
        Agents join a goal in the workspace; the ones they work on show up here.
      </Regent.Primitives.empty_state>
      <div
        :for={{project, i} <- Enum.with_index(@work)}
        :if={@goals?}
        id={"fleet-recent-work-project-#{i}"}
        class="recent-project"
      >
        <h3>
          <.link patch={ProjectPage.path(@fleet_id, project.name)}>
            {project.title}
          </.link>
        </h3>
        <ul :if={project.goals != []} class="recent-work__list">
          <li :for={goal <- project.goals} class="recent-goal">
            <p class="recent-goal__title">{goal}</p>
          </li>
        </ul>
      </div>

      <.link
        id="fleet-recent-work-workspace"
        patch={"#{Regents.Keyfleet.Fleets.path(@fleet_id)}/workspace"}
      >
        Open the workspace
      </.link>
    </section>
    """
  end

  # Each channel's tag on its lines in the feed.
  @tags %{chat: "Chat", work: "Work", keys: "Keys", votes: "Votes"}

  attr :id, :string, required: true
  attr :item, :map, required: true, doc: "an item of `Regents.Keyfleet.Activity`"
  attr :fleet, :map, required: true
  attr :params, :map, required: true

  # One thing that happened, as one line of the feed: when, its channel's
  # tag, and the sentence `RegentsWeb.Keyfleet.ActivityLines` tells. A problem raised
  # with an item stands out.
  defp activity_line(assigns) do
    channel = ActivityLines.channel(assigns.item)

    assigns =
      assign(assigns,
        parts: ActivityLines.parts(assigns.item),
        channel: channel,
        tag: Map.fetch!(@tags, channel),
        tone: tone(assigns.item)
      )

    ~H"""
    <li
      id={@id}
      class="activity-line"
      data-line
      data-layout-id={@id}
      data-kind={@item.kind}
      data-channel={@channel}
      data-tone={@tone}
    >
      <Time.local
        id={"#{@id}-at"}
        class="activity-line__time"
        at={@item.at}
        as={:clock}
        title_as={:moment}
      />
      <span class="activity-line__tag">{@tag}</span>
      <p :if={@item.kind == :votes} class="activity-line__text activity-line__votes">
        <.activity_part
          id={"#{@id}-proposal"}
          part={{:proposal, @item.facts.number}}
          fleet_id={@fleet.fleet_id}
          params={@params}
        />
        <.vote_tally
          yes={@item.facts.totals.yes}
          no={@item.facts.totals.no}
          abstain={@item.facts.totals.abstain}
        />
      </p>
      <p :if={@item.kind != :votes} class="activity-line__text">
        <.activity_part
          :for={{part, i} <- Enum.with_index(@parts)}
          id={"#{@id}-#{i}"}
          part={part}
          fleet_id={@fleet.fleet_id}
          params={@params}
        />
      </p>
    </li>
    """
  end

  defp tone(%{kind: :linked, facts: %{relation: "contradicts"}}), do: "disagreement"
  defp tone(_item), do: nil

  attr :id, :string, required: true
  attr :part, :any, required: true
  attr :fleet_id, :string, required: true
  attr :params, :map, required: true

  # A key opens its profile over this page, in one of four colours so each
  # Key's lines are easy to follow; an item or a room opens its own page, and
  # a wallet shows as every address does.
  # Everything a member wrote is text, never markup.
  defp activity_part(%{part: {:key, token_id, agent}} = assigns) do
    assigns = assign(assigns, token_id: token_id, agent: agent)

    ~H"""
    <.link
      patch={KeyLinks.key_path(@fleet_id, @token_id, @params)}
      data-key={@token_id}
      data-hue={rem(@token_id, 4)}
    >{ActivityLines.key_name(@token_id, @agent)}</.link>
    """
  end

  defp activity_part(%{part: {:item, id, title}} = assigns) do
    assigns = assign(assigns, id: id, title: title)

    ~H|“<.link patch={WorkspacePage.item_path(@fleet_id, @id)} data-item-link={@id}>{@title}</.link>”|
  end

  defp activity_part(%{part: {:room, slug, name}} = assigns) do
    assigns = assign(assigns, slug: slug, name: name)

    ~H|<.link patch={KeyLinks.room_path(@fleet_id, @slug)} data-room={@slug}>{@name}</.link>|
  end

  defp activity_part(%{part: {:agent, name}} = assigns) do
    assigns = assign(assigns, :name, name)
    ~H|<span class="activity-line__agent">{@name}</span>|
  end

  defp activity_part(%{part: {:address, wallet}} = assigns) do
    assigns = assign(assigns, :wallet, wallet)
    ~H|<Regent.Primitives.address id={@id} address={@wallet} />|
  end

  defp activity_part(%{part: {:quote, text}} = assigns) do
    assigns = assign(assigns, :text, ActivityLines.plain(text))
    ~H|<q class="activity-line__quote">{@text}</q>|
  end

  defp activity_part(%{part: {:proposal, number}} = assigns) do
    assigns = assign(assigns, :number, number)

    ~H|<.link patch={ProposalsPage.detail_path(@fleet_id, @number)} data-proposal={@number}>{ActivityLines.proposal_name(
  @number
)}</.link>|
  end

  defp activity_part(assigns), do: ~H"{@part}"

  attr :fleet, :map, required: true

  # A fleet not yet on Base shows a still picture of its map as it will open,
  # while the bar above says it isn't on Base yet.
  defp map_preview(assigns) do
    ~H"""
    <div
      id={"fleet-preview-#{@fleet.fleet_id}"}
      class="key-map-preview fleet-unsold"
      phx-hook="FleetPreview"
      phx-update="ignore"
      data-layout={@fleet.layout}
      data-minted="0"
      aria-hidden="true"
    >
    </div>
    """
  end

  attr :fleet_id, :string, required: true
  attr :view, :atom, required: true, values: [:map, :members]

  # The Keys tab shows who holds which Key, as a list (where it opens) or as the grid.
  defp keys_switch(assigns) do
    ~H"""
    <nav id={"fleet-keys-#{@view}"} class="fleet-keys-switch" aria-label="Show Keys as">
      <.link
        id={"fleet-keys-#{@view}-list"}
        patch={KeyLinks.members_path(@fleet_id)}
        aria-current={if @view == :members, do: "page"}
      >
        List
      </.link>
      <.link
        id={"fleet-keys-#{@view}-grid"}
        patch={KeyLinks.map_path(@fleet_id)}
        aria-current={if @view == :map, do: "page"}
      >
        Grid
      </.link>
    </nav>
    """
  end

  attr :fleet, :map, required: true

  # The controls only move the map, so they never wait on the page; a search
  # asks the page which Keys to mark, and the map writes what was found. The map
  # draws itself once its script loads; until then it says so, and the list
  # of keys below still has every key. While "Buy Key" is open, the Key on
  # offer stands out on the map and the note under it names that Key.
  defp key_map(assigns) do
    assigns = assign(assigns, :map, "#key-map-#{assigns.fleet.fleet_id}")

    ~H"""
    <section id="fleet-map" class="fleet-map" aria-labelledby="fleet-map-title">
      <h2 id="fleet-map-title" class="visually-hidden">Key map</h2>

      <div class="fleet-map-controls">
        <.keys_switch fleet_id={@fleet.fleet_id} view={:map} />
        <Regent.Primitives.button
          :if={@fleet.progress.next_token_id}
          id="key-map-next"
          variant="secondary"
          phx-click={JS.dispatch("keymap:next", to: @map)}
        >
          Next Key
        </Regent.Primitives.button>
        <Regent.Primitives.button
          :if={@fleet.signed_in? && @fleet.held != nil}
          id="key-map-mine"
          variant="secondary"
          phx-click={JS.dispatch("keymap:mine", to: @map)}
        >
          Your Keys
        </Regent.Primitives.button>
        <form
          :if={@fleet.levels != []}
          id="key-map-level"
          class="fleet-map-level"
          phx-submit={JS.dispatch("keymap:level", to: @map)}
        >
          <label for="key-map-level-choice" class="visually-hidden">Go to level</label>
          <span class="fleet-map-level__choice">
            <select id="key-map-level-choice" name="level">
              <option :for={level <- @fleet.levels} value={level}>Level {level}</option>
            </select>
            <Regent.Icons.icon name="chevron-down" />
          </span>
          <Regent.Primitives.button type="submit" variant="secondary">Go</Regent.Primitives.button>
        </form>
        <form
          id="key-map-find"
          class="fleet-map-level fleet-map-find"
          role="search"
          phx-submit={JS.dispatch("keymap:find", to: @map)}
        >
          <label for="key-map-find-q" class="visually-hidden">Find a Key or an address’s Keys</label>
          <input
            id="key-map-find-q"
            name="q"
            type="search"
            placeholder="Key number or 0x address"
            maxlength="42"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
          />
          <Regent.Primitives.button type="submit" variant="secondary">
            Find
          </Regent.Primitives.button>
        </form>
      </div>

      <div
        id={"key-map-#{@fleet.fleet_id}"}
        class="key-map"
        phx-hook="KeyMap"
        phx-update="ignore"
        data-layout={@fleet.layout}
        data-selected={@fleet.chosen_key}
        tabindex="0"
        role="application"
        aria-roledescription="Key map"
        aria-label="Key map"
        aria-describedby="key-map-help"
      >
        <Placeholder.placeholder label="Loading the map" shape="area" role={nil} />
      </div>

      <div class="fleet-map-notes">
        <Regent.Primitives.tip id="key-map-help" label="About the Key map">
          Drag to pan, click or press Enter to inspect a Key. Switch to List to browse holders.
        </Regent.Primitives.tip>
        <p id="key-map-selected" role="status">
          <span class="key-map-selected__chosen">
            {if @fleet.chosen_key,
              do: "Key #{grouped(@fleet.chosen_key)} chosen.",
              else: "No Key chosen yet."}
          </span>
        </p>
        <ul class="fleet-map-legend" aria-label="Key status">
          <li data-state="sold">Sold</li>
          <li data-state="next">Next</li>
          <li data-state="unsold">Unsold</li>
        </ul>
        <output
          id="key-map-found"
          class="key-map-found"
          name="found"
          form="key-map-find"
          for="key-map-find-q"
          phx-update="ignore"
        ></output>
      </div>
    </section>
    """
  end

  @doc "Atomic USDC shown exactly, since it is what a purchase pays."
  def usdc(atoms), do: "#{ProposalsPage.units(atoms, 6)} USDC"

  @doc "What the fleet's page does with the events it sends."
  # "Show earlier" adds the next page of the hall's feed below the ones
  # shown, up to five pages. A run of transfers the two pages share reads as
  # one line: the lowest line on show gives way to it.
  def handle_event(
        "activity_earlier",
        _params,
        %{assigns: %{activity: %{cursor: cursor, pages: pages} = activity}} = socket
      )
      when cursor != nil and pages < @activity_pages do
    %{items: items, cursor: next} =
      Activity.page(activity.fleet_id, cursor, ShellLive.reads_as(socket, activity.fleet_id))

    {socket, ids, lines} =
      case FeedLines.join(activity.last, read_lines(activity.fleet_id, items)) do
        {:joined, lines} ->
          {stream_delete_by_dom_id(socket, :activity, activity_dom_id(activity.last)),
           MapSet.delete(activity.ids, activity.last.id), lines}

        {:apart, lines} ->
          {socket, activity.ids, lines}
      end

    {:noreply,
     socket
     |> assign(:activity, %{
       activity
       | cursor: next,
         pages: pages + 1,
         ids: MapSet.union(ids, MapSet.new(lines, & &1.id)),
         last: List.last(lines)
     })
     |> stream(:activity, lines)}
  end

  def handle_event("activity_earlier", _params, socket), do: {:noreply, socket}

  # A Club Key opens from its Pass's number, since it waits for whoever holds
  # that Pass; its window shows Claim to them. A number with no Key says so
  # beside the field.
  def handle_event(
        "open_pass_key",
        %{"pass" => pass},
        %{assigns: %{fleet: %{deployed?: true} = fleet}} = socket
      ) do
    case FleetPage.chosen_key(fleet.progress, pass) do
      nil ->
        {:noreply, assign(socket, :pass_note, pass_note(pass))}

      token_id ->
        {:noreply,
         socket
         |> assign(:pass_note, nil)
         |> push_patch(
           to: KeyLinks.key_path(fleet.fleet_id, token_id, socket.assigns.fleet_params)
         )}
    end
  end

  def handle_event("open_pass_key", _params, socket), do: {:noreply, socket}

  def handle_event(
        "validate_quote",
        %{"quote" => %{"body" => body} = params},
        %{assigns: %{quotes: %{form: %{}}}} = socket
      )
      when is_binary(body),
      do:
        {:noreply,
         update(socket, :quotes, &%{&1 | form: AshPhoenix.Form.validate(&1.form, params)})}

  def handle_event("validate_quote", _params, socket), do: {:noreply, socket}

  # The words go to the person's agent, which decides where to quote them.
  def handle_event(
        "send_quote",
        %{"quote" => %{"body" => body} = params},
        %{assigns: %{quotes: %{form: %{}}}} = socket
      )
      when is_binary(body) do
    %{fleet: %{fleet_id: fleet_id}, quotes: quotes} = socket.assigns

    actor = ShellLive.human_actor(socket)

    case AshPhoenix.Form.submit(quotes.form, params: params) do
      # Sent words are never offered to send again: the box empties and says
      # so even when the requests can't be read again.
      {:ok, _request} ->
        {:noreply, sent_quotes(socket, fleet_id, actor)}

      {:error, form} ->
        {:noreply, assign(socket, :quotes, %{quotes | form: form, note: quote_refusal(form)})}
    end
  end

  def handle_event("send_quote", _params, socket), do: {:noreply, socket}

  # The map on a deployed fleet's page asks for its keys when it loads and
  # every time it reconnects; it is left unanswered when they can't be read.
  def handle_event("keymap_ready", _params, %{assigns: %{fleet: %{deployed?: true}}} = socket) do
    %{fleet_id: fleet_id, progress: progress} = socket.assigns.fleet
    actor = ShellLive.human_actor(socket)

    case PageRead.run("map", fn -> KeyMap.snapshot(fleet_id, progress, actor) end) do
      {:ok, snapshot} -> {:reply, snapshot, socket}
      {:error, _failure} -> {:noreply, socket}
    end
  end

  def handle_event("keymap_ready", _params, socket), do: {:noreply, socket}

  # The map asks for the close-ups of the keys it has in view, and goes
  # without them when they can't be read.
  def handle_event(
        "keymap_pictures",
        %{"keys" => token_ids},
        %{assigns: %{fleet: %{deployed?: true} = fleet}} = socket
      ) do
    case PageRead.run("map", fn -> KeyMap.pictures(fleet.deck, fleet.progress, token_ids) end) do
      {:ok, pictures} -> {:reply, pictures, socket}
      {:error, _failure} -> {:reply, %{pictures: []}, socket}
    end
  end

  def handle_event("keymap_pictures", _params, socket), do: {:noreply, socket}

  # A search of the map: the Keys found come back for the map to mark.
  def handle_event(
        "find_keys",
        %{"q" => query},
        %{assigns: %{fleet: %{deployed?: true} = fleet}} = socket
      ),
      do: {:reply, KeyMap.find(fleet.fleet_id, fleet.progress, query), socket}

  def handle_event("find_keys", _params, socket), do: {:noreply, socket}

  # A key chosen on the map goes into the address and its profile opens over
  # the page, so Back closes it. Chosen while a profile is open, it takes that
  # profile's place in the address, so closing still just closes.
  def handle_event(
        "select_key",
        %{"token_id" => token_id},
        %{assigns: %{fleet: %{deployed?: true} = fleet}} = socket
      ) do
    if KeyMap.choosable?(fleet.progress, token_id) do
      {:noreply,
       push_patch(socket,
         to: KeyLinks.key_path(fleet.fleet_id, token_id, socket.assigns.fleet_params),
         replace: socket.assigns.key_profile != nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_key", _params, socket), do: {:noreply, socket}

  # Why the words sent to the person's agent were not sent.
  defp quote_refusal(form) do
    errors = form.source.source.errors

    case Enum.find(
           errors,
           &(is_struct(&1, NoPairedAgentError) or is_struct(&1, QuoteLimitError))
         ) do
      %NoPairedAgentError{} ->
        "Pair an agent first"

      %QuoteLimitError{limit: limit, retry_after: seconds} ->
        "You've sent #{limit} in the last hour. Try again in #{RoomsLive.minutes(seconds)}."

      nil ->
        if Enum.any?(errors, &match?(%{field: :body}, &1)),
          do: "Write up to 1,000 characters",
          else: "That didn’t go through. Try again."
    end
  end

  # Why the Pass number sent opened no Key.
  defp pass_note(pass) when is_binary(pass) do
    case Integer.parse(pass) do
      {number, ""} ->
        if BoxLimit.too_long?(pass, FleetPage.longest_key()),
          do: "That Pass number is too long",
          else: "No Key for Pass #{number}"

      _not_a_number ->
        "Enter a Pass number"
    end
  end

  defp pass_note(_pass), do: "Enter a Pass number"

  @doc """
  A member's hall reads its feed again from the top, as many pages as are
  shown, once for the burst of notices about the fleet on show that asked
  for it. A wait begun for a fleet the page has since left reads nothing. A
  read again that fails keeps what the hall shows; the next notice reads again.
  """
  def handle_info(
        {:refresh_activity, fleet_id},
        %{assigns: %{activity: %{fleet_id: fleet_id}}} = socket
      ) do
    socket = assign(socket, :activity_refresh, nil)

    case PageRead.run("fleet", fn -> socket |> reread_activity(nil) |> reread_quotes() end) do
      {:ok, reread} -> {:noreply, reread}
      {:error, _failure} -> {:noreply, socket}
    end
  end

  def handle_info({:refresh_activity, _fleet_id}, socket), do: {:noreply, socket}

  @doc """
  The fleet named in the address, with a page of its keys and what's happening
  in it; or `:unreadable` when the database couldn't be read.
  """
  def read_fleet(socket, params, place) do
    case PageRead.run("fleet", fn -> show_fleet(socket, params, place) end) do
      {:ok, socket} -> socket
      {:error, _failure} -> show_without_keys(socket, :unreadable, params, place)
    end
  end

  defp show_fleet(socket, %{"fleet_id" => fleet_id} = params, place) do
    actor = ShellLive.human_actor(socket)

    fleet = Fleets.get_fleet!(fleet_id, actor: actor)

    cond do
      fleet == nil ->
        show_without_keys(socket, %{fleet_id: fleet_id, name: nil}, params, place)

      Fleets.coming_soon?(fleet_id, fleet) ->
        show_without_keys(socket, soon(fleet_id, fleet), params, place)

      true ->
        show_with_keys(socket, fleet, params, place, actor)
    end
  end

  defp soon(fleet_id, fleet),
    do: %{
      fleet_id: fleet_id,
      name: fleet.name,
      coming_soon?: true,
      layout: Presets.preset(fleet_id),
      facts: soon_facts(fleet_id)
    }

  # What a coming-soon fleet will sell: how many Keys, when it has a limit, and
  # the price of its first Key, or for Classic, whose 1,024 prices are a fixed
  # table, of its first and last.
  defp soon_facts(fleet_id) do
    supply = Presets.max_supply(fleet_id)
    first = Presets.issue_price(fleet_id, 1)

    price =
      cond do
        first == nil ->
          nil

        Presets.preset(fleet_id) == :classic ->
          last = Presets.issue_price(fleet_id, supply)
          String.trim_trailing(usdc(first), " USDC") <> "–" <> usdc(last)

        true ->
          "From #{usdc(first)}"
      end

    Enum.reject([{"Keys", supply && grouped(supply)}, {"Price", price}], &(elem(&1, 1) == nil))
  end

  # Any other fleet: its figures and what's happening in it. Its Member List
  # reads its own page of holders. The readings it shows are named by the
  # fleet's own record, never by the address, and heard before they are
  # fetched, so one that lands in between still reaches the page. A hall
  # whose reading isn't there yet says the fleet couldn't be read, and one
  # whose reading still has the fleet coming soon shows it so; neither is
  # read for the page instead.
  defp show_with_keys(socket, %{id: fleet_id} = fleet, params, place, actor) do
    shown = view(socket.assigns.fleet_place, socket.assigns.fleet_params || %{})
    wanted = view(place, params)
    socket = follow_shared(socket, fleet_id, wanted)

    case figures(socket, fleet_id, fleet, wanted) do
      :coming_soon ->
        show_without_keys(socket, soon(fleet_id, fleet), params, place)

      :unread ->
        show_without_keys(socket, :unreadable, params, place)

      figures ->
        feed = feed_on_return(shown, wanted)
        show_open(socket, fleet, figures, params, place, feed, actor)
    end
  end

  defp show_open(socket, %{id: fleet_id} = fleet, figures, params, place, feed, actor) do
    %{deployed?: deployed?, current?: current?, progress: progress, now: now} = figures

    socket
    |> assign(:fleet, %{
      fleet_id: fleet_id,
      name: fleet.name,
      coming_soon?: false,
      chain_id: fleet.chain_id,
      chain_fleet_id: fleet.chain_fleet_id,
      rewards_address: fleet.rewards_address,
      usdc_address: fleet.usdc_address,
      deployed?: deployed?,
      current?: current?,
      progress: progress,
      buy: if(deployed?, do: FleetPage.next_sale(fleet_id, progress)),
      rooms: Rooms.list_rooms!(fleet_id, ShellLive.reads_as(socket, fleet_id)),
      polls?: ShellLive.may_read?(socket, fleet_id, :polls),
      layout: Presets.preset(fleet_id),
      chosen_key: if(deployed?, do: FleetPage.chosen_key(progress, params["key"])),
      levels: if(deployed?, do: KeyMap.levels(progress), else: []),
      signed_in?: actor != nil,
      given?: Presets.given?(fleet_id),
      deck: Map.take(fleet, [:id, :deck_hash, :deck_size]),
      club_claims: fleet.club_claims_address,
      held: FleetPage.held(fleet, actor),
      open_proposals: FleetProposals.open(fleet_id)
    })
    |> assign(fleet_params: params, fleet_place: place, pass_note: nil)
    |> show_agents()
    |> follow_feed(fleet_id, place, feed, now)
    |> read_quotes(fleet_id, actor)
    |> SeasonPanel.show(fleet_id, view(place, params), now)
  end

  # How far the fleet has sold, and with it, for a hall drawn from the
  # fleet's reading, that reading (`now`): the feed's first page and "Trying
  # now" come from it too. Any other page reads the sales itself.
  defp figures(socket, fleet_id, fleet, view) do
    if from_reading?(socket, fleet_id, view) do
      case FleetNow.fetch(fleet_id) do
        {%{coming_soon?: false} = reading, _degraded?} ->
          fleet_id |> sales(reading) |> Map.put(:now, reading)

        {%{coming_soon?: true}, _degraded?} ->
          :coming_soon

        nil ->
          :unread
      end
    else
      deployed? = fleet.manager_address != nil

      %{
        deployed?: deployed?,
        current?: deployed? and Chain.fresh?(fleet_id),
        progress: if(deployed?, do: Chain.progress(fleet_id)),
        now: nil
      }
    end
  end

  # The sales a reading holds, as `Regents.Keyfleet.Chain.progress/1` gives them.
  defp sales(fleet_id, %{deployed?: deployed?, current?: current?, minted: minted}),
    do: %{
      deployed?: deployed?,
      current?: current?,
      progress: if(deployed?, do: Presets.progress(fleet_id, minted))
    }

  @doc """
  Whether the page on show is a hall drawn from the fleet's reading every
  such page shares (`RegentsWeb.Keyfleet.FleetNow`): the hall's own view, shown to a
  reader who isn't a member. Its sales, feed and "Recent Work" are never read
  for the page itself; only what is the reader's own is.
  """
  def from_reading?(
        %{assigns: %{fleet: %{fleet_id: fleet_id}, fleet_place: place, fleet_params: params}} =
          socket
      ),
      do: from_reading?(socket, fleet_id, view(place, params))

  def from_reading?(_socket), do: false

  defp from_reading?(socket, fleet_id, view),
    do: view == :hall and not ShellLive.member?(socket, fleet_id)

  # The feed is held while the fleet's own views are on show: a member's
  # read for them, anyone else's drawn from the reading on the hall alone,
  # the one view of it they see. The Treasury and the Workspace leave it,
  # and coming back to the hall draws it afresh.
  defp follow_feed(socket, fleet_id, :fleet, feed, %{} = now),
    do: read_activity(socket, fleet_id, feed, now)

  defp follow_feed(socket, fleet_id, :fleet, feed, nil) do
    if ShellLive.member?(socket, fleet_id),
      do: read_activity(socket, fleet_id, feed, nil),
      else: leave_feed(socket)
  end

  defp follow_feed(socket, _fleet_id, _place, _feed, _now), do: leave_feed(socket)

  defp leave_feed(socket) do
    socket
    |> assign(activity: nil, activity_refresh: nil)
    |> stream(:activity, [], reset: true)
  end

  # The feed's lines leave the page with the hall, so coming back from
  # another view draws them again.
  defp feed_on_return(shown, wanted),
    do: if(shown != :hall and wanted == :hall, do: :redrawn, else: :kept)

  @doc """
  What the signed-in person has sent their agent to quote in the fleet, with
  a fresh box to send more: `%{paired?, form, requests, note}`, the latest
  requests first, each with the room it was quoted in once it was. Nil for
  anyone not signed in.
  """
  def read_quotes(socket, fleet_id, actor, note \\ nil)

  def read_quotes(socket, _fleet_id, nil, _note), do: assign(socket, :quotes, nil)

  def read_quotes(socket, fleet_id, actor, note) do
    assign(socket, :quotes, %{
      paired?: Agents.has_paired_agent?(actor),
      form: quote_form(fleet_id, actor),
      requests: Rooms.my_quote_requests!(fleet_id, actor: actor),
      note: note
    })
  end

  @doc """
  The signed-in person paired or unpaired an agent: the hall's Message box
  switches between Pair New Agent and the quote form without losing a draft
  while they remain paired.
  """
  def agents_changed(%{assigns: %{fleet: %{fleet_id: fleet_id}, quotes: %{} = quotes}} = socket) do
    case ShellLive.human_actor(socket) do
      %Human{} = actor ->
        if Agents.has_paired_agent?(actor) == quotes.paired?,
          do: socket,
          else: read_quotes(socket, fleet_id, actor)

      nil ->
        assign(socket, :quotes, nil)
    end
  end

  def agents_changed(socket), do: socket

  defp sent_quotes(socket, fleet_id, actor) do
    case PageRead.run("fleet", fn -> read_quotes(socket, fleet_id, actor, "Sent") end) do
      {:ok, read} ->
        read

      {:error, _failure} ->
        update(socket, :quotes, &%{&1 | form: quote_form(fleet_id, actor), note: "Sent"})
    end
  end

  defp quote_form(fleet_id, actor) do
    QuoteRequest
    |> AshPhoenix.Form.for_create(:ask,
      actor: actor,
      as: "quote",
      transform_params: fn params, _action ->
        params |> Map.take(["body"]) |> Map.put("fleet_id", fleet_id)
      end
    )
    |> to_form()
  end

  # A post quoting the person is a new line in a room, so their requests are
  # read again with the hall; the box keeps what they are typing.
  defp reread_quotes(
         %{assigns: %{quotes: %{form: %{}} = quotes, fleet: %{fleet_id: fleet_id}}} = socket
       ),
       do:
         assign(socket, :quotes, %{
           quotes
           | requests: Rooms.my_quote_requests!(fleet_id, actor: ShellLive.human_actor(socket))
         })

  defp reread_quotes(socket), do: socket

  # A hall drawn from the fleet's reading reads the person's requests again
  # with it only while one of them is still waiting for their agent, so a
  # new reading costs everyone else nothing.
  defp reread_waiting_quotes(%{assigns: %{quotes: %{requests: requests}}} = socket) do
    if Enum.any?(requests, &is_nil(&1.quoted_in_slug)), do: reread_quotes(socket), else: socket
  end

  defp reread_waiting_quotes(socket), do: socket

  # A fleet there is not, or one coming soon: its name at most, and no keys
  # or activity to read.
  defp show_without_keys(socket, fleet, params, place) do
    socket
    |> SharedFigures.follow(:fleet, [])
    |> SeasonPanel.leave()
    |> assign(
      fleet: fleet,
      fleet_params: params,
      fleet_place: place,
      pass_note: nil,
      quotes: nil,
      activity: nil,
      activity_refresh: nil
    )
    |> stream(:fleet_who, [], reset: true)
    |> stream(:activity, [], reset: true)
  end

  # The hall's feed: the fleet's activity, newest first, read for the
  # reader or drawn from the fleet's reading (`now`). A page moving within
  # the same fleet keeps the pages it shows, drawn again when the hall comes
  # back into view; another fleet, or a reader who now sees the feed another
  # way, starts from its first page. The cursor for the next page stays
  # here, on the server.
  defp read_activity(
         %{assigns: %{activity: %{fleet_id: fleet_id, reading?: reading?}}} = socket,
         fleet_id,
         :kept,
         now
       )
       when reading? == is_map(now),
       do: socket

  defp read_activity(
         %{assigns: %{activity: %{fleet_id: fleet_id, reading?: reading?}}} = socket,
         fleet_id,
         :redrawn,
         now
       )
       when reading? == is_map(now),
       do: reread_activity(socket, now)

  defp read_activity(socket, fleet_id, _feed, now) do
    {items, socket} =
      socket
      |> assign(activity: %{fleet_id: fleet_id, pages: 1}, activity_refresh: nil)
      |> activity_pages(now)

    stream(socket, :activity, items, reset: true)
  end

  # Lines already on the page stay where they are drawn: the gone ones leave
  # and the new ones go in at their place, so the list's motion moves only
  # what changed. A reset would empty the list before its motion records it.
  defp reread_activity(%{assigns: %{activity: %{ids: shown}}} = socket, now) do
    {items, socket} = activity_pages(socket, now)
    kept = socket.assigns.activity.ids

    socket =
      shown
      |> MapSet.difference(kept)
      |> Enum.reduce(socket, &stream_delete_by_dom_id(&2, :activity, activity_dom_id(%{id: &1})))

    items
    |> Enum.with_index()
    |> Enum.reduce(socket, fn {item, at}, socket ->
      if MapSet.member?(shown, item.id),
        do: stream_insert(socket, :activity, item),
        else: stream_insert(socket, :activity, item, at: at)
    end)
  end

  # A member's feed: as many pages as are shown, read again from the top as
  # they read them, with "Recent Work".
  defp activity_pages(%{assigns: %{activity: %{fleet_id: fleet_id, pages: pages}}} = socket, nil) do
    {items, cursor, read} =
      FleetPage.activity_pages(fleet_id, pages, ShellLive.reads_as(socket, fleet_id))

    lines = read_lines(fleet_id, items)

    {lines,
     assign(socket, :activity, %{
       fleet_id: fleet_id,
       cursor: cursor,
       pages: read,
       ids: MapSet.new(lines, & &1.id),
       last: List.last(lines),
       empty?: lines == [],
       recent_work: FleetPage.read_recent_work(fleet_id),
       reading?: false
     })}
  end

  # Anyone else's: the reading's first page and "Recent Work". The pages they
  # asked for beyond it with "Show earlier" stay below it as they were read,
  # with the cursor after them. A first page that shares no line with them
  # starts the feed again from itself, so no gap opens between the two.
  defp activity_pages(%{assigns: %{activity: activity}} = socket, %{
         feed: feed,
         recent_work: recent_work
       }) do
    lines = FeedLines.lines(feed.items, feed.receivers)
    first = MapSet.new(lines, & &1.id)
    shown = Map.get(activity, :ids, MapSet.new())

    {lines, ids, cursor, pages, last} =
      if activity.pages > 1 and not MapSet.disjoint?(shown, first) do
        lines = FeedLines.over(lines, shown)

        {lines, MapSet.union(shown, MapSet.new(lines, & &1.id)), activity.cursor, activity.pages,
         activity.last}
      else
        {lines, first, feed.cursor, 1, List.last(lines)}
      end

    {lines,
     assign(socket, :activity, %{
       fleet_id: activity.fleet_id,
       cursor: cursor,
       pages: pages,
       ids: ids,
       last: last,
       empty?: MapSet.size(ids) == 0,
       recent_work: recent_work,
       reading?: true
     })}
  end

  # A page of the fleet's activity as the hall's lines, with the wallet each
  # transfer on it went to.
  defp read_lines(fleet_id, items),
    do: FeedLines.lines(items, Activity.receivers(fleet_id, items))

  @doc """
  One read for a burst of notices about the fleet on show; the wait names
  the fleet it was begun for. Only a member's feed is read again: anyone
  else's is drawn from the fleet's reading when it changes
  (`shared_changed/2`), and reads nothing on a notice.
  """
  def refresh_activity_soon(
        %{assigns: %{activity: %{fleet_id: fleet_id}, activity_refresh: nil}} = socket,
        fleet_id
      ) do
    if ShellLive.member?(socket, fleet_id) do
      # A burst of changes is read once, after `:fleet_feed_wait_ms`.
      wait = Application.fetch_env!(:regents, :keyfleet_fleet_feed_wait_ms)
      Process.send_after(self(), {:refresh_activity, fleet_id}, wait)
      assign(socket, :activity_refresh, fleet_id)
    else
      socket
    end
  end

  def refresh_activity_soon(socket, _fleet_id), do: socket

  @doc """
  What the feed needs to know of the pages read, and never the cursor:
  whether anything is there, whether earlier items are a press of "Show
  earlier" away or past the pages it shows, and what the fleet is working on.
  """
  def now_shown(nil), do: nil

  def now_shown(%{cursor: cursor, pages: pages, empty?: empty?, recent_work: recent_work}) do
    earlier =
      cond do
        cursor == nil -> nil
        pages < @activity_pages -> :more
        true -> :elsewhere
      end

    %{empty?: empty?, earlier: earlier, recent_work: recent_work}
  end

  @doc "The id of a line of the hall's feed on the page."
  def activity_dom_id(%{id: id}), do: "fleet-feed-" <> String.replace(id, ":", "-")

  @doc """
  Sales and transfers move the figures, the key on offer, the levels the map
  can go to and the Keys the reader holds. A hall drawn from the fleet's
  reading reads only the reader's Keys here; its figures come with the
  reading a moment later (`shared_changed/2`).
  """
  def refresh_sales(%{assigns: %{fleet: %{fleet_id: fleet_id} = fleet}} = socket) do
    if from_reading?(socket) do
      held = FleetPage.held(fleet.deck, ShellLive.human_actor(socket))
      assign(socket, :fleet, %{fleet | held: held})
    else
      progress = Chain.progress(fleet_id)

      assign(socket, :fleet, %{
        fleet
        | progress: progress,
          current?: Chain.fresh?(fleet_id),
          buy: FleetPage.next_sale(fleet_id, progress),
          levels: KeyMap.levels(progress),
          held: FleetPage.held(fleet.deck, ShellLive.human_actor(socket))
      })
    end
  end

  @doc "Keys changed hands: the Member List, when it is on show, reads its page again."
  def refresh_members(%{assigns: %{fleet_place: place, fleet_params: params}} = socket) do
    if view(place, params) == :members, do: MemberList.refresh("fleet-members")
    socket
  end

  # The readings the fleet's page shows, heard from before they are read:
  # "Here now" and the bar's count of agents, and for a hall drawn from
  # the fleet's reading, that reading.
  defp follow_shared(socket, fleet_id, view) do
    now = if from_reading?(socket, fleet_id, view), do: [FleetNow.key(fleet_id)], else: []

    SharedFigures.follow(
      socket,
      :fleet,
      [Here.fleet_key(fleet_id), FleetProposals.list_key(fleet_id)] ++ now
    )
  end

  # Before the fleet's first reading, the agents and holders are said to be uncounted,
  # never shown as none. The agents go to the page as they are drawn, each
  # line as the reader's class reads it (`Here.seen_by/2`), and aren't kept:
  # each reading draws them all again.
  defp show_agents(%{assigns: %{fleet: %{fleet_id: fleet_id} = fleet}} = socket) do
    {agents, here, holders} =
      case SharedFigures.reading(Here.fleet_key(fleet_id)) do
        %{agents: agents, here: here, holders: holders} -> {agents, here, holders}
        nil -> {[], nil, nil}
      end

    member? = ShellLive.member?(socket, fleet_id)
    agents = Enum.map(agents, &%{&1 | seen: Here.seen_by(&1.seen, member?)})

    socket
    |> assign(
      :fleet,
      Map.merge(fleet, %{agents_shown: length(agents), agents_here: here, holders: holders})
    )
    |> stream(:fleet_who, agents, reset: true)
  end

  @doc """
  A shared reading the page hears has changed: \"Here now\" is drawn
  again, or a hall drawn from the fleet's reading draws its sales, feed and
  "Recent Work" from the new one. Each is matched on the fleet it is for, so
  a reading of a fleet the page has left changes nothing, and one of the
  fleet on show still lands right after it.
  """
  def shared_changed(
        %{assigns: %{fleet: %{fleet_id: fleet_id}}} = socket,
        {:keyfleet_fleet_agents, fleet_id}
      ),
      do: show_agents(socket)

  def shared_changed(
        %{assigns: %{fleet: %{fleet_id: fleet_id, coming_soon?: false}}} = socket,
        {:keyfleet_fleet_now, fleet_id}
      ) do
    if from_reading?(socket), do: show_reading(socket), else: socket
  end

  def shared_changed(
        %{assigns: %{fleet: %{fleet_id: fleet_id, coming_soon?: false} = fleet}} = socket,
        {:keyfleet_fleet_proposals, fleet_id}
      ),
      do: assign(socket, :fleet, %{fleet | open_proposals: FleetProposals.open(fleet_id)})

  def shared_changed(socket, _key), do: socket

  @doc """
  The reader's class in the fleet on show has changed (`Regents.Keyfleet.Access`).
  A hall shown to someone who is no longer a member is drawn from the
  fleet's reading from now on, in place of what they read as one; one
  shown to a new member stops hearing the reading, and its next notice
  reads the feed as theirs. The polls show in the sidebar for a member only,
  and the "Season" panel moves to what the new class reads of it.
  """
  def class_changed(
        %{assigns: %{fleet: %{fleet_id: fleet_id, coming_soon?: false} = fleet}} = socket,
        fleet_id
      ) do
    %{fleet_place: place, fleet_params: params} = socket.assigns
    view = view(place, params)

    socket =
      socket
      |> assign(:fleet, %{fleet | polls?: ShellLive.may_read?(socket, fleet_id, :polls)})
      |> follow_shared(fleet_id, view)
      |> show_agents()

    with true <- from_reading?(socket),
         {%{coming_soon?: false} = reading, _degraded?} <- FleetNow.fetch(fleet_id) do
      socket
      |> show_sales(reading)
      |> read_activity(fleet_id, :new, reading)
      |> SeasonPanel.show(fleet_id, view, reading)
    else
      _member_or_unread -> SeasonPanel.show(socket, fleet_id, view, nil)
    end
  end

  def class_changed(socket, _fleet_id), do: socket

  # The hall drawn again from the fleet's newest reading. A reading with the
  # fleet no longer open changes nothing on it.
  defp show_reading(
         %{assigns: %{fleet: %{fleet_id: fleet_id}, activity: %{ids: _shown}}} = socket
       ) do
    case FleetNow.fetch(fleet_id) do
      {%{coming_soon?: false} = reading, _degraded?} ->
        socket
        |> show_sales(reading)
        |> reread_activity(reading)
        |> reread_waiting_quotes()
        |> SeasonPanel.show(fleet_id, :hall, reading)

      _not_open ->
        socket
    end
  end

  defp show_reading(socket), do: socket

  # The figures move with the reading as `refresh_sales/1` moves them, once
  # the fleet is on Base.
  defp show_sales(
         %{assigns: %{fleet: %{fleet_id: fleet_id, deployed?: true} = fleet}} = socket,
         %{deployed?: true} = reading
       ) do
    %{current?: current?, progress: progress} = sales(fleet_id, reading)

    assign(socket, :fleet, %{
      fleet
      | progress: progress,
        current?: current?,
        buy: FleetPage.next_sale(fleet_id, progress),
        levels: KeyMap.levels(progress)
    })
  end

  defp show_sales(socket, _reading), do: socket

  def tell_map_chosen(
        %{assigns: %{fleet: %{fleet_id: fleet_id, chosen_key: chosen}}} = socket,
        %{fleet_id: fleet_id, chosen_key: shown}
      )
      when chosen != shown,
      do: push_event(socket, "keymap:select", %{token_id: chosen})

  def tell_map_chosen(socket, _shown), do: socket
end
