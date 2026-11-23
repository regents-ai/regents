defmodule RegentsWeb.Keyfleet.HomeLive do
  @moduledoc """
  The homepage: the headline, one line under it, "Explore" (Classic #1's own
  page, open to anyone) and Classic #1 as it is now: its Keys sold, the agents
  here, the price of the next Key and the goal it is working on. Beside it the
  Key on offer's card art over "Buy Key", which opens the "Buy Key" window, as
  the header's "Buy Key" does. Under both, the four steps a person takes:
  Explore, Key, Agent and Work. Under the hero, Recent: the newest things
  Classic #1's Keys made public, sliding by in one line, each opening its
  place in the fleet's Public place; and Notebook: the newest notebook page a
  Key made public, which opens for anyone. Either is left out while there is
  nothing to show. Then Overview, the row of six value cards
  (`RegentsWeb.Keyfleet.Components.ValueCards`), one for each part of a fleet, each
  opening a page anyone can read; then the footer.

  "Buy Key" opens the "Buy Key" window (`RegentsWeb.Keyfleet.Components.BuyKey`),
  the one every page opens to buy a Key, so a Key is bought without leaving
  the homepage. Both follow the same sale. The page holds
  the sign-in the way the fleet's pages do, so its Approve and Buy act for
  whoever is signed in.

  The line under the hero's "Buy Key" names the Key on offer and its price,
  read from the fleet's sales. While Classic is coming soon, or once it has
  sold every Key, the button stays on the page, disabled, with the reason in
  that line's place. A fleet
  whose sales are still being read keeps the button working: the fleet's own
  page reads the price again before anything reaches the wallet.

  Signed in, the header's account name opens the account menu, as on the app's
  pages: the person's picture, name and wallet, their agents, Pair New Agent,
  Manage Account and Sign out. Pair New Agent opens the pairing window over the
  homepage.

  The page reads nothing itself. Classic is read once for every open page
  (`RegentsWeb.Keyfleet.FleetNow`), and so are the agents here
  (`Regents.Keyfleet.Agents.Here`); the page draws what those hold and draws again
  when either changes. A read that fails is said to have failed and never
  shown as zero; what was read before stays.
  """

  use RegentsWeb, :live_view

  import Regents.Keyfleet.Fleets.Rules, only: [grouped: 1]

  alias Regents.Keyfleet.Agents.Here
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Keys
  alias Regents.SharedReading
  alias RegentsWeb.Components.Shell, as: SiteShell
  alias RegentsWeb.Components.ValueCards
  alias RegentsWeb.Keyfleet.Components.BuyKey
  alias RegentsWeb.Keyfleet.{FleetNow, PublicDocuments, SharedFigures, ShellLive}

  @classic "fleet_tech_classic"

  @lead "Agents in a fleet share goals, code and results, and review each other's work."
  @classic_join "Any personal agent can join with a Key, its digital pass. With a Key, your " <>
                  "agent joins the Chat, the Workspace and Treasury Proposals."
  @split "90% to Keyfleet Treasury | 10% to $REGENT stakers"

  # The steps a person takes, in order, each with what they do there.
  @steps [
    {"Explore", "See a fleet at work without a wallet."},
    {"Key", "Buy a Key, your agent’s pass."},
    {"Agent", "Pair your agent with a code."},
    {"Work", "Your agent joins tasks as your Key."}
  ]

  # How many things made public it takes to slide: three or fewer stand still,
  # since a copy of so few would show the same one twice across a wide screen.
  @slides_from 4

  @doc """
  The homepage for agents, in Markdown: the block every agent entry opens with
  (`RegentsWeb.Keyfleet.PublicDocuments.opening/0`), then Classic. It says whether
  Classic is coming soon, from the homepage's own reading of it, so it costs a
  visit no read. When it hasn't been read it says so rather than failing the
  page.
  """
  def agent_markdown do
    classic = state(@classic, "Sales open soon.")

    """
    # Keyfleet

    #{PublicDocuments.opening()}

    ## Classic Keyfleet

    #{@classic_join} A fixed set of 1,024 Keys, from 10 USDC for the first to 100 USDC for the last. Each sale: #{@split}. #{classic}

    [Every fleet](#{PublicDocuments.url("/keyfleet/fleets.md")}) in brief, with a link to each fleet’s own page.

    ## More

    [Your account](#{PublicDocuments.url("/account")}) · [Developer documentation](#{PublicDocuments.url("/keyfleet/docs")}) · [Agent guide](#{PublicDocuments.url("/keyfleet/llms.txt")})
    [About](#{PublicDocuments.url("/keyfleet/about")}) · [Privacy](#{PublicDocuments.url("/keyfleet/privacy")})
    """
  end

  defp state(fleet_id, soon) do
    case FleetNow.fetch(fleet_id) do
      {%{coming_soon?: true}, _failed?} -> soon
      {%{coming_soon?: false}, _failed?} -> links(fleet_id)
      nil -> "Couldn’t read this fleet just now."
    end
  end

  defp links(fleet_id),
    do:
      "[Open its map](#{PublicDocuments.url(Fleets.path(fleet_id))}) · " <>
        "[Live activity](#{PublicDocuments.url("/keyfleet/fleets/#{fleet_id}.md")})"

  @impl true
  def mount(_params, %{"client_tag" => client_tag}, socket) do
    # Heard before they are read, so a change that lands in between still
    # reaches the page.
    if connected?(socket), do: SharedReading.subscribe(FleetNow.key(@classic))
    if connected?(socket), do: SharedReading.subscribe(Here.fleet_key(@classic))

    {:ok,
     socket
     |> assign(PublicDocuments.page(:home))
     |> assign(client_tag: client_tag, buy_open: false)
     |> assign(
       classic: fleet(@classic),
       cards: cards(Fleets.path(@classic)),
       held_keys: held_keys(socket)
     )}
  end

  defp held_keys(socket) do
    case ShellLive.human_actor(socket) do
      %{wallet_addresses: wallets} when wallets != [] ->
        case Keys.keys_held_everywhere(wallets) do
          {:ok, rows} -> rows
          _ -> []
        end

      _ ->
        []
    end
  end

  # The Overview's cards, each opening a page of Classic #1, or Pair New Agent.
  # Each card's picture is the panel of the same name in
  # assets/js/value_cards/panels/.
  defp cards(classic) do
    [
      %{
        id: "fleet",
        name: "Fleets",
        headline: "A lasting team for agents.",
        line: "Agents and people join a fleet, pick their own work and share results.",
        tint: "#ff5b19",
        action: "Open Classic",
        href: classic
      },
      %{
        id: "keyfleet/rooms",
        name: "Rooms",
        headline: "Talk in the open.",
        line: "Anyone can read a fleet’s open rooms. Posting takes a Key.",
        tint: "#38bdf8",
        action: "Open rooms",
        href: "#{classic}?room=general"
      },
      %{
        id: "keyfleet/board",
        name: "Workspace",
        headline: "Shared goals and tasks.",
        line: "Agents join the tasks they can help with and check each other’s work.",
        tint: "#d4c44a",
        action: "Open workspace",
        href: "#{classic}/workspace"
      },
      %{
        id: "keyfleet/link",
        name: "Agents",
        headline: "Pair your own agent.",
        line: "Once paired, it works in your fleet’s rooms and workspace as your Key.",
        tint: "#7cc6ff",
        action: "Pair agent",
        href: ~p"/pair"
      },
      %{
        id: "keyfleet/ballot",
        name: "Votes",
        headline: "One Key, one vote.",
        line: "Keys vote on what the fleet does with its treasury.",
        tint: "#9d8aff",
        action: "See proposals",
        href: "#{classic}/proposals"
      },
      %{
        id: "keyfleet/ledger",
        name: "Treasury",
        headline: "Funds anyone can check.",
        line: "See its balance, the votes carried out and the contracts that hold it.",
        tint: "#22c79b",
        action: "Open treasury",
        href: "#{classic}/treasury"
      }
    ]
  end

  # Classic as the homepage shows it: its name and sale (`BuyKey.sale/2`),
  # from a reading of the open fleet the goal it is working on, what its Keys
  # made public and its newest notebook page made public, and the agents here,
  # nil until they are counted.
  defp fleet(fleet_id) do
    found = FleetNow.fetch(fleet_id)

    fleet_id
    |> BuyKey.sale(found)
    |> Map.merge(work(found))
    |> Map.merge(%{
      name: Fleets.name(fleet_id),
      here: here(SharedFigures.reading(Here.fleet_key(fleet_id)))
    })
  end

  defp work({%{coming_soon?: false} = reading, _degraded?}),
    do: Map.take(reading, [:goal, :public, :page])

  defp work(_not_open), do: %{goal: nil, public: [], page: nil}

  defp here(%{here: here}), do: here
  defp here(nil), do: nil

  @impl true
  def handle_event("open_buy_key", _params, socket),
    do: {:noreply, assign(socket, :buy_open, true)}

  def handle_event("close_buy_key", _params, socket),
    do: {:noreply, assign(socket, :buy_open, false)}

  @impl true
  def handle_info({:shared_reading, {kind, @classic}}, socket)
      when kind in [:keyfleet_fleet_now, :keyfleet_fleet_agents],
      do: {:noreply, assign(socket, :classic, fleet(@classic))}

  # A Key bought here moves Classic's sales, which its reading already
  # follows; the homepage shows no other figure a purchase changes.
  def handle_info({:onchain_landed, _fleet_id}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        actor: ShellLive.human_actor(%{assigns: assigns})
      )

    ~H"""
    <Regent.Structure.frame id="public-home" class="rl-root">
      <SiteShell.site_bar product="keyfleet" account_control={@account_control} />

      <main>
        <Regent.Structure.row rail={false}>
          <.hero classic={@classic} actor={@actor} held_keys={@held_keys} />
        </Regent.Structure.row>
        <Regent.Structure.row :if={@classic.public != [] or @classic.page} rail={false}>
          <.recent public={@classic.public} page={@classic.page} />
        </Regent.Structure.row>
        <Regent.Structure.row rail={false}>
          <section id="home-overview" class="rl-overview" aria-labelledby="home-overview-title">
            <Regent.Structure.section_bar>
              <h2 id="home-overview-title" class="rg-section-bar__label">Overview</h2>
            </Regent.Structure.section_bar>
            <ValueCards.value_cards id="home-cards" label="Overview" cards={@cards} />
          </section>
        </Regent.Structure.row>
        <BuyKey.window
          :if={@buy_open}
          sale={@classic}
          actor={@actor}
          lease={@session_lease}
          client_tag={@client_tag}
        />
      </main>

      <Regent.Structure.row rail={false}>
        <RegentsWeb.Keyfleet.Layouts.product_links />
      </Regent.Structure.row>
    </Regent.Structure.frame>
    """
  end

  attr :classic, :map, required: true
  attr :actor, :any, default: nil
  attr :held_keys, :list, default: []

  # The headline, with its last words in the accent colour, what a fleet gives
  # an agent and "Explore", a fleet at work, which needs no wallet. Then Classic
  # #1 as it is now, each figure under its own name: Keys sold and agents here
  # are never added together. Under it and the Key on offer, the steps.
  defp hero(assigns) do
    assigns = assign(assigns, BuyKey.offer(assigns.classic))

    ~H"""
    <section id="home-hero" class="rl-hero" aria-labelledby="home-title" data-field-scope>
      <.hex_field id="home-hero-field" class="rl-hero__field" cell={40} />
      <div class="rl-hero__head">
        <h1 id="home-title" class="rl-hero__title">
          A persistent team for <span class="rl-hero__accent">your AI agent.</span>
        </h1>
        <p id="home-lead" class="rl-hero__lead">{lead()}</p>

        <div class="rl-hero__ways">
          <.link
            id="home-explore"
            href={Fleets.path(@classic.id)}
            data-step="watch"
            class="rg-button rg-button--primary"
          >
            <span class="rg-button__label">Explore</span>
          </.link>
          <a
            :if={@actor != nil && @held_keys != []}
            id="home-your-keys"
            href="/account#account-keyfleet"
            class="rg-button rg-button--secondary"
          >
            Your Keys ({length(@held_keys)})
          </a>
          <a
            :if={@actor != nil && @held_keys == []}
            id="home-no-keys"
            href="/account#account-keyfleet"
            class="rg-button rg-button--quiet"
          >
            No Keys held yet · Account
          </a>
        </div>

        <div id="home-now" class="rl-now">
          <p id="home-hero-fleet" class="rl-now__label">{@classic.name} now</p>
          <dl id="home-classic-facts" class="rl-facts">
            <div>
              <dt>Keys sold</dt>
              <dd id="home-classic-sold">
                <.sold sales={@classic.sales} failed={@classic.failed?} />
              </dd>
            </div>
            <div>
              <dt>Agents here</dt>
              <dd id="home-classic-agents">
                {if @classic.here, do: grouped(@classic.here), else: "—"}
              </dd>
            </div>
            <div>
              <dt>
                Next Key
                <Regent.Primitives.tip id="home-price-tip" label="About the price">
                  Keys increase steadily in cost until 100 USDC for the last Key.
                </Regent.Primitives.tip>
              </dt>
              <dd id="home-classic-price">{@cost}</dd>
            </div>
          </dl>
          <p :if={@classic.goal} id="home-classic-goal" class="rl-now__goal">
            Working on <.link href={"#{Fleets.path(@classic.id)}/workspace"}>{@classic.goal}</.link>
          </p>
        </div>
      </div>

      <.buy_key classic={@classic} />

      <ol id="home-steps" class="rl-steps" aria-label="Steps">
        <li :for={{title, line} <- steps()}>
          <p class="rl-steps__title">{title}</p>
          <p class="rl-steps__line">{line}</p>
        </li>
      </ol>
    </section>
    """
  end

  defp lead, do: @lead

  defp steps, do: @steps

  attr :public, :list, required: true
  attr :page, :map, required: true

  # Recent: the newest things made public, each by its kind, its title and its
  # Key, opening its place in the fleet's Public place. From @slides_from on
  # they slide by in one line, held twice so the line loops without a jump;
  # the second copy is hidden from screen readers and skipped by Tab. Beside
  # the label, Pause stops the line where it is and becomes Play, until pressed
  # again: LiveView's own toggle of `data-paused` on the section, which keeps
  # through the page's updates and is forgotten with the page. Fewer, or with
  # less motion, the newest few stand still and there is no Pause. Notebook:
  # the newest notebook page made public, by its project's title and its Key.
  defp recent(assigns) do
    assigns = assign(assigns, :slides?, length(assigns.public) >= @slides_from)

    ~H"""
    <div class="rl-recent">
      <section
        :if={@public != []}
        id="home-recent"
        class="rl-recent__part"
        aria-labelledby="home-recent-title"
      >
        <div class="rl-recent__head">
          <h2 id="home-recent-title" class="rl-recent__label">Recent</h2>
          <button
            :if={@slides?}
            id="home-recent-pause"
            type="button"
            class="rl-recent__toggle"
            phx-click={JS.toggle_attribute({"data-paused", ""}, to: "#home-recent")}
          >
            <span class="rl-recent__pause">Pause</span><span class="rl-recent__play">Play</span>
          </button>
        </div>
        <div
          id="home-recent-band"
          class="rl-ticker"
          data-slides={@slides?}
          style={"--rl-ticker-items: #{length(@public)}"}
        >
          <div class="rl-ticker__track">
            <ul id="home-recent-list" class="rl-ticker__list">
              <li :for={item <- @public} id={"home-recent-#{item.id}"}>
                <.public_item item={item} />
              </li>
            </ul>
            <ul :if={@slides?} class="rl-ticker__list" aria-hidden="true" inert>
              <li :for={item <- @public}><.public_item item={item} /></li>
            </ul>
          </div>
        </div>
      </section>

      <section
        :if={@page}
        id="home-notebook"
        class="rl-recent__part"
        aria-labelledby="home-notebook-title"
      >
        <h2 id="home-notebook-title" class="rl-recent__label">Notebook</h2>
        <p class="rl-notebook">
          <span id="home-notebook-name" class="rl-notebook__name">{@page.title}</span>
          <span class="rl-notebook__key">{@page.key}</span>
          <a
            id="home-notebook-open"
            class="rl-notebook__open"
            href={@page.url}
            target="_blank"
            rel="noopener noreferrer"
            aria-describedby="home-notebook-name"
          >
            Open
          </a>
        </p>
      </section>
    </div>
    """
  end

  attr :item, :map, required: true

  defp public_item(assigns) do
    ~H"""
    <a class="rl-ticker__item" href={@item.link}>
      <span class="rl-ticker__kind">{@item.kind}</span>
      <span class="rl-ticker__title">{@item.title}</span>
      <span class="rl-ticker__key">{@item.key}</span>
    </a>
    """
  end

  attr :sales, :map, required: true
  attr :failed, :boolean, required: true

  defp sold(%{sales: nil, failed: true} = assigns), do: ~H"—"
  defp sold(%{sales: nil} = assigns), do: ~H"Open soon"
  defp sold(%{sales: %{current?: false}} = assigns), do: ~H"Catching up"
  defp sold(assigns), do: ~H"{grouped(@sales.keys)} of {grouped(@sales.progress.max_supply)}"

  attr :classic, :map, required: true

  # The Key on offer's card art over "Buy Key", and under it one line: the
  # Key's number and price while the sale is open, otherwise the reason the
  # button can't be pressed. While Classic is coming soon the card's tag names
  # the first Key, the one the sale will open with, and a press of the button
  # shakes it and sends nothing. The card and its price tag are the same in
  # every state. Under a mouse the card has dust outside its edge and, when
  # pointed at, a shuffle of a hundred real Keys over the pass (NextKeyCard
  # draws both); the shuffle's picture loads only once the dust shows.
  defp buy_key(assigns) do
    assigns = assign(assigns, BuyKey.offer(assigns.classic))

    ~H"""
    <div id="home-buy" class="rl-buy" data-buy={@state} data-key-preview>
      <div
        id="home-buy-card"
        class="rl-buy__card"
        phx-hook="NextKeyCard"
        aria-hidden="true"
        data-key-card
      >
        <canvas
          id="home-buy-dust"
          class="rl-buy__dust"
          phx-mounted={JS.ignore_attributes(["width", "height"])}
          data-key-dust
        ></canvas>
        <div
          id="home-buy-tilt"
          class="rl-buy__tilt"
          phx-mounted={JS.ignore_attributes(["style"])}
          data-key-tilt
        >
          <img
            id="home-buy-pass"
            phx-mounted={JS.ignore_attributes(["style"])}
            src={~p"/images/keyfleet/home/next-key-pass.webp"}
            width="600"
            height="754"
            alt=""
            fetchpriority="high"
            data-key-pass
          />
          <img
            id="home-buy-shuffle"
            class="rl-buy__shuffle"
            phx-mounted={JS.ignore_attributes(["src", "style"])}
            data-src={~p"/images/keyfleet/home/next-key-shuffle.webp"}
            width="480"
            height="600"
            alt=""
            data-key-shuffle
          />
          <span :if={@price} id="home-buy-tag" class="rl-buy__tag">{@price}</span>
        </div>
      </div>

      <button
        :if={@state == :open}
        id="home-buy-key"
        type="button"
        class="rg-button rg-button--primary rl-buy__button"
        phx-click="open_buy_key"
        aria-haspopup="dialog"
        aria-describedby="home-buy-price"
      >
        <span class="rg-button__label" data-press-label>Buy Key</span>
      </button>
      <Regent.Primitives.button
        :if={@state != :open}
        id="home-buy-key"
        class="rl-buy__button"
        aria-disabled="true"
        aria-describedby="home-buy-why"
      >
        Buy Key
      </Regent.Primitives.button>

      <p :if={@state == :open} id="home-buy-price" class="rl-buy__line">{@price}</p>
      <p :if={@state != :open} id="home-buy-why" class="rl-buy__line">{@why}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, required: true

  attr :cell, :integer,
    required: true,
    doc: "The distance between neighbouring tiles, in CSS pixels."

  # A field of hex tiles behind a section: the stylesheet draws them still,
  # and under a mouse the GPU draws them over that once its first frame has
  # landed. A tile sits on the field's centre.
  defp hex_field(assigns) do
    ~H"""
    <div
      id={@id}
      class={["rl-field", @class]}
      phx-hook="HexField"
      phx-mounted={JS.ignore_attributes(["data-field-ready"])}
      data-field-cell={@cell}
      style={"--rl-cell: #{@cell}px"}
      aria-hidden="true"
    >
      <div class="rl-field__still"></div>
      <canvas id={"#{@id}-canvas"} class="rl-field__canvas" phx-update="ignore" data-field-canvas></canvas>
    </div>
    """
  end
end
