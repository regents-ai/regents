defmodule RegentsWeb.Keyfleet.HarbourSeaLive do
  @moduledoc """
  The swarm city behind the product's pages: one disc for each of the most
  recently active holders and each holder whose Keys the agents here act as,
  flying to the district of their last action and circling its towers
  (`RegentsWeb.Keyfleet.HarbourCrew`).

  On a fleet's pages the ships are that fleet's holders, one for each account
  with all its Keys, showing the Key it writes as; anywhere else they are the
  latest holders of every open fleet. The visitor's own ship comes first, then
  the agents' here, then the most recent, twenty-four at most. The city takes
  no presses until the button beside a fleet's name (`lift/1`) lifts the page
  away; then a drag turns it, the mouse over a disc names its Key, and pressing
  the disc or its name opens its card (`agent_card/1`). Its districts lead to the fleet's Public room, workspace and treasury
  (`HarbourCrew.districts/1`), and a bar at the top names the fleet, brings the
  page back (as Escape does) and opens its Chat or Workspace.

  The root layout renders it beside the page's own LiveView
  (`RegentsWeb.Router` marks the pages that have it), so it keeps running
  while the visitor moves between pages; the page tells it where it is with
  "show_page". It takes the shell's own sign-in check and shows nothing the
  page itself would not. Each move to another fleet, or to every fleet, spends
  one of the page's address's `keyfleet_sea_moves` (`Regents.Limits`, keyed by
  the page's `client_tag`); past them the sea stays as it is drawn until the
  allowance starts again. An address longer than any page's moves nothing.

  A fleet's ships are drawn from what every visitor who isn't a member sees
  alike, `RegentsWeb.Keyfleet.FleetNow` and `Regents.Keyfleet.Agents.Here`, read once for every
  open page. Only a
  member's ships are read as the visitor, since a member sees more (rooms
  other than the Public room, every item's title). Which ships are the visitor's own
  is read as the visitor, when the fleet comes on show and when its Keys
  change hands.
  """

  use RegentsWeb, :live_view

  alias Regents.Keyfleet.Access
  alias Regents.Keyfleet.Activity
  alias Regents.Keyfleet.Agents.Here
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Rooms
  alias Regents.Limits
  alias Regents.SharedReading

  alias RegentsWeb.Endpoint

  alias RegentsWeb.Keyfleet.{
    FleetNow,
    HarbourCrew,
    KeyLinks,
    PageRead,
    RouteCatalog,
    SharedFigures,
    ShellLive
  }

  alias RegentsWeb.Read
  alias RegentsWeb.Router

  alias Phoenix.Socket.Broadcast
  alias RegentsWeb.Live.Session

  # Notices about what the visitor reads as themselves are answered by one
  # read a moment later, and each visitor's moment is spread over two seconds
  # more, so the open pages of a fleet's members don't all read in the same
  # instant. It only delays a read of the visitor's own view.
  @reread_after 1_000
  @spread 2_000

  # The longest page address the sea reads, in bytes.
  @longest_path 2_048

  @doc """
  The sea, as the root layout places it on the page `conn` draws. The page's
  live session is the page's own: its hooks watch navigation, which LiveView
  refuses for a LiveView the router did not mount, so it is left out here and
  this LiveView takes the shell's sign-in check itself (`mount/3`).
  """
  def sea(conn) do
    outside = %{conn | private: Map.delete(conn.private, :phoenix_live_view)}

    live_render(outside, __MODULE__,
      container: {:div, class: "harbour-sea"},
      session: Session.render_context(conn)
    )
  end

  # `fleets` are the fleets on show, each with the visitor's class in it, and
  # `own` the visitor's Keys in each, under the account they were read for.
  # `public` holds each fleet's ships as anyone who isn't a member sees them,
  # `crew` the ships of the fleets the visitor is a member of, read as them.
  # `due` is what the next read for the visitor must read again, and
  # `crew_again?` whether their ships are read again once the read under way
  # lands.
  @impl true
  def mount(params, %{"client_tag" => client_tag} = session, socket) do
    case admit(params, session, socket) do
      {:cont, socket} ->
        {:ok,
         assign(socket,
           client_tag: client_tag,
           path: nil,
           shown: nil,
           fleets: [],
           own: {nil, %{}},
           public: %{},
           crew: %Read{},
           crew_again?: false,
           topics: [],
           watched: [],
           due: MapSet.new(),
           agent: nil
         ), layout: false}

      {:halt, socket} ->
        {:ok, socket}
    end
  end

  # The shell's sign-in (`RegentsWeb.Live.Session`): a connection is refused as
  # the shell's is, and every event, notice and read after it checks the sign-in
  # again first. The hook also watches navigation, which this LiveView never
  # has and LiveView refuses to a LiveView the router did not mount, so the
  # sign-in is taken as if routed and the watch on navigation is taken off again.
  defp admit(params, session, socket) do
    case Session.on_mount(:load_human, params, session, %{socket | router: Router}) do
      {:cont, socket} ->
        {:cont, %{detach_hook(socket, :session_authority_params, :handle_params) | router: nil}}

      {:halt, socket} ->
        {:halt, %{socket | router: nil}}
    end
  end

  # The page on show, by its address. A new address closes the card; a new
  # fleet brings its ships.
  @impl true
  def handle_event("show_page", %{"path" => path}, socket)
      when is_binary(path) and byte_size(path) <= @longest_path do
    socket =
      if path == socket.assigns.path, do: socket, else: assign(socket, path: path, agent: nil)

    {:noreply, kept(socket, fn -> show(socket, shown(path)) end)}
  end

  def handle_event("show_agent", %{"id" => id}, socket) when is_binary(id) do
    if ship(on_sea(socket.assigns), id),
      do: {:noreply, assign(socket, agent: id)},
      else: {:noreply, socket}
  end

  def handle_event("close_agent", _params, socket), do: {:noreply, assign(socket, :agent, nil)}

  # A page or ship sent without its address or name, or a page's address
  # longer than any page's.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # A new reading of a fleet the visitor isn't a member of redraws its ships.
  # One that has gone leaves the sea as it is drawn. A new reading of the
  # agents here in a fleet the visitor is a member of reads its ships again.
  @impl true
  def handle_info({:shared_reading, {kind, fleet_id} = key}, socket)
      when kind in [:keyfleet_fleet_now, :keyfleet_fleet_agents] do
    cond do
      key not in socket.assigns.watched -> {:noreply, socket}
      {fleet_id, :member} in socket.assigns.fleets -> {:noreply, crew_soon(socket)}
      true -> {:noreply, socket |> draw([fleet_id]) |> close_sailed()}
    end
  end

  # Anything new in a fleet the visitor is a member of is a nudge to read its
  # ships again, once for a burst; Keys changing hands, to read again which
  # are the visitor's and whether they are a member. Nothing else a fleet says
  # moves a ship: a new reading of a treasury's balances, every five minutes, least
  # of all.
  def handle_info({:reread, shown}, %{assigns: %{shown: shown, due: due}} = socket) do
    socket = assign(socket, :due, MapSet.new())
    {:noreply, kept(socket, fn -> reread(socket, due) end)}
  end

  def handle_info({:reread, _left}, socket), do: {:noreply, socket}
  def handle_info(%Broadcast{}, socket), do: {:noreply, crew_soon(socket)}
  def handle_info({:graph_head, _fleet, _run, _mark}, socket), do: {:noreply, crew_soon(socket)}
  def handle_info({:graph_notable, _fleet}, socket), do: {:noreply, crew_soon(socket)}
  def handle_info({:proposals_changed, _fleet}, socket), do: {:noreply, crew_soon(socket)}

  def handle_info({:keys_changed, fleet_id, _keys}, socket) do
    if List.keymember?(socket.assigns.fleets, fleet_id, 0),
      do: {:noreply, reread_soon(socket, {:keys, fleet_id})},
      else: {:noreply, socket}
  end

  def handle_info(_notice, socket), do: {:noreply, socket}

  # The visitor's ships land; when more was asked of them while they loaded,
  # they are read once more.
  @impl true
  def handle_async({Read, :crew, _generation} = name, result, socket) do
    socket = socket |> Read.settle(name, result) |> close_sailed()

    if socket.assigns.crew_again?,
      do: {:noreply, socket |> assign(:crew_again?, false) |> read_crew()},
      else: {:noreply, socket}
  end

  # The card of a Key that has sailed off the sea closes with it.
  defp close_sailed(%{assigns: %{agent: nil}} = socket), do: socket

  defp close_sailed(socket) do
    if ship(on_sea(socket.assigns), socket.assigns.agent),
      do: socket,
      else: assign(socket, :agent, nil)
  end

  defp show(%{assigns: %{shown: shown}} = socket, shown), do: socket

  # A move to another fleet, or to every fleet, spends one of the page's
  # address's moves; past them the sea stays as it is drawn.
  defp show(socket, shown) do
    case Limits.spend(:keyfleet_sea_moves, socket.assigns.client_tag) do
      :ok -> bring(socket, shown)
      :limited -> socket
    end
  end

  # The visitor's class and Keys in each fleet are read before anything is
  # heard, so a read that fails leaves the sea, and what it hears, as it was.
  defp bring(socket, shown) do
    actor = ShellLive.human_actor(socket)
    fleets = Enum.map(fleets(shown), &{&1, Access.class(actor, &1)})
    own = Map.new(fleets, fn {fleet_id, _class} -> {fleet_id, owned(actor, fleet_id)} end)

    socket
    |> assign(
      shown: shown,
      fleets: fleets,
      own: {reader(socket.assigns.access_context), own},
      due: MapSet.new()
    )
    |> follow(actor)
    |> draw(for {fleet_id, class} <- fleets, class != :member, do: fleet_id)
    |> read_crew()
  end

  # What a reread names, read again: the class and Keys of each fleet whose
  # Keys changed hands, and the ships of the fleets the visitor is a member
  # of when anything in them changed. A fleet the visitor left is drawn from
  # its shared reading again; one they joined is read as them.
  defp reread(socket, due) do
    actor = ShellLive.human_actor(socket)
    reader = reader(socket.assigns.access_context)
    rechecked = for {:keys, fleet_id} <- due, do: fleet_id
    {owner, own} = socket.assigns.own
    own = if owner == reader, do: own, else: %{}

    fleets =
      for {fleet_id, class} <- socket.assigns.fleets do
        {fleet_id, if(fleet_id in rechecked, do: Access.class(actor, fleet_id), else: class)}
      end

    own = Map.merge(own, Map.new(rechecked, &{&1, owned(actor, &1)}))

    redrawn =
      for {fleet_id, class} <- fleets, class != :member, fleet_id in rechecked, do: fleet_id

    crew? = :crew in due or Enum.any?(rechecked, &({&1, :member} in fleets))

    socket =
      socket |> assign(fleets: fleets, own: {reader, own}) |> follow(actor) |> draw(redrawn)

    if crew?, do: read_crew(socket), else: socket
  end

  # The sea stays as it is when the visitor's part can't be read; the next
  # page, or the next notice about the fleets it shows, reads it again.
  defp kept(socket, read) do
    case PageRead.run("harbour", read) do
      {:ok, read_socket} -> read_socket
      {:error, _failure} -> socket
    end
  end

  defp crew_soon(socket), do: reread_soon(socket, :crew)

  # The first notice of a burst sets the moment; the rest join it.
  defp reread_soon(socket, reason) do
    %{due: due, shown: shown} = socket.assigns

    if MapSet.size(due) == 0 do
      wait = @reread_after + :rand.uniform(@spread + 1) - 1
      Process.send_after(self(), {:reread, shown}, wait)
    end

    assign(socket, :due, MapSet.put(due, reason))
  end

  # The fleet whose page is at `path`, when the shell shows that fleet: one
  # that is open. Anywhere else, every open fleet (`:public`).
  defp shown(path) do
    with %{route: route} <- Phoenix.Router.route_info(Router, "GET", path, Endpoint.host()),
         %{fleet_id: fleet_id} when is_binary(fleet_id) <-
           Enum.find(RouteCatalog.entries(), &(&1.path_pattern == route)),
         true <- open?(fleet_id) do
      fleet_id
    else
      _elsewhere -> :public
    end
  end

  defp fleets(:public), do: Enum.filter(Fleets.catalog_ids(), &open?/1)
  defp fleets(fleet_id), do: [fleet_id]

  # Whether a fleet is open, as its shared reading last read it: the
  # reading's `coming_soon?` is `Fleets.coming_soon?/2` of the fleet's record,
  # the rule `Fleets.open_fleet_ids/0` reads too. A fleet not read yet is as
  # the catalog marks it, as the homepage shows it.
  defp open?(fleet_id) do
    case FleetNow.fetch(fleet_id) do
      {%{coming_soon?: coming_soon?}, _degraded?} -> not coming_soon?
      nil -> not Fleets.coming_soon?(fleet_id, nil)
    end
  end

  # What the visitor hears of each fleet on show. A member hears what the
  # shell hears for their class: its rooms, its workspace and its votes. Anyone
  # else hears its shared reading, which hears those for everyone. Everyone
  # hears its agents here, whose Keys fly too. A signed-in
  # visitor also hears its Keys, which change which ships are theirs and
  # whether they are a member; a signed-out one holds none.
  defp follow(socket, actor) do
    %{fleets: fleets, topics: topics_was, watched: watched_was} = socket.assigns
    topics = Enum.flat_map(fleets, fn {fleet_id, class} -> topics(fleet_id, class, actor) end)

    watched =
      Enum.flat_map(fleets, fn
        {fleet_id, :member} -> [Here.fleet_key(fleet_id)]
        {fleet_id, _class} -> [FleetNow.key(fleet_id), Here.fleet_key(fleet_id)]
      end)

    Enum.each(topics_was -- topics, &Phoenix.PubSub.unsubscribe(Regents.PubSub, &1))
    Enum.each(topics -- topics_was, &Phoenix.PubSub.subscribe(Regents.PubSub, &1))
    Enum.each(watched_was -- watched, &SharedReading.unsubscribe/1)
    Enum.each(watched -- watched_was, &SharedReading.subscribe/1)
    assign(socket, topics: topics, watched: watched)
  end

  defp topics(fleet_id, :member, _actor),
    do: [
      Rooms.topic(fleet_id, :member),
      Graph.topic(fleet_id, :member),
      Proposals.topic(fleet_id),
      Keys.topic(fleet_id)
    ]

  defp topics(_fleet_id, _class, nil), do: []
  defp topics(fleet_id, _class, _actor), do: [Keys.topic(fleet_id)]

  # The ships of `fleet_ids` from their shared readings, heard first. A fleet
  # whose reading is absent keeps the ships it has; a fleet gone from the sea
  # takes its ships with it.
  defp draw(socket, fleet_ids) do
    %{fleets: fleets, public: public} = socket.assigns

    public =
      Enum.reduce(
        fleet_ids,
        Map.take(public, Enum.map(fleets, &elem(&1, 0))),
        fn fleet_id, public ->
          case FleetNow.fetch(fleet_id) do
            {%{coming_soon?: false, feed: %{items: items}, faces: faces}, _degraded?} ->
              {agents, here_faces} = here(fleet_id)

              Map.put(
                public,
                fleet_id,
                HarbourCrew.ships(fleet_id, items, agents, Map.merge(here_faces, faces))
              )

            {%{coming_soon?: true}, _degraded?} ->
              Map.put(public, fleet_id, [])

            nil ->
              public
          end
        end
      )

    assign(socket, :public, public)
  end

  # The ships of the fleets the visitor is a member of are read beside the
  # page, as the visitor, after listening to those fleets, so a change that
  # lands while they load still reaches them. Each fleet's class is read again
  # first, since the one held since it came on show may have lapsed: a fleet
  # the visitor is no longer a member of is read as anyone sees it. One read
  # runs at a time: asked again while one loads, they are read once more when
  # it lands (`handle_async/3`).
  defp read_crew(%{assigns: %{crew: %Read{state: :loading}}} = socket),
    do: assign(socket, :crew_again?, true)

  defp read_crew(socket) do
    actor = ShellLive.human_actor(socket)

    case for({fleet_id, :member} <- socket.assigns.fleets, do: fleet_id) do
      [] ->
        socket

      fleet_ids ->
        Read.start(socket, :crew, reader(socket.assigns.access_context), fn ->
          {:ok,
           Map.new(fleet_ids, fn fleet_id ->
             %{items: items} =
               Activity.page(fleet_id, nil,
                 actor: actor,
                 context: Access.context(actor, fleet_id, Access.class(actor, fleet_id))
               )

             {agents, here_faces} = here(fleet_id)
             faces = Keys.faces(fleet_id, HarbourCrew.keys(items))

             {fleet_id, HarbourCrew.ships(fleet_id, items, agents, Map.merge(here_faces, faces))}
           end)}
        end)
    end
  end

  # The agents here in a fleet and who holds their Keys and writes as which, from the reading every
  # open page shares; none while it has not been read.
  defp here(fleet_id) do
    case SharedFigures.reading(Here.fleet_key(fleet_id)) do
      %{agents: agents, faces: faces} -> {agents, faces}
      nil -> {[], %{}}
    end
  end

  # The Keys the visitor holds in a fleet; a signed-out visitor holds none.
  defp owned(actor, fleet_id), do: MapSet.new(Keys.held_keys(actor, fleet_id), & &1.token_id)

  # The ships on the sea: each fleet's, as the visitor's class there sees it,
  # the visitor's own ship first, then the most recently active. What was read
  # for the visitor shows only while they are signed in as they were then: a
  # sign-in that ends while the page is open takes it away with it. A fleet
  # the visitor has just joined shows as anyone sees it until their own read
  # of it lands; one they have left shows only as anyone sees it.
  defp drawn(fleets, public, crew, {owner, own}, access_context) do
    reader = reader(access_context)
    read = if crew.owner == reader, do: crew.value || %{}, else: %{}
    own = if owner == reader, do: own, else: %{}

    fleets
    |> Enum.flat_map(fn {fleet_id, class} ->
      mine = Map.get(own, fleet_id, MapSet.new())

      ships =
        if class == :member,
          do: read[fleet_id] || public[fleet_id],
          else: public[fleet_id]

      for ship <- ships || [],
          do: Map.put(ship, :own?, Enum.any?(ship.keys, &MapSet.member?(mine, &1)))
    end)
    |> HarbourCrew.sea()
  end

  defp on_sea(assigns),
    do: drawn(assigns.fleets, assigns.public, assigns.crew, assigns.own, assigns.access_context)

  defp ship(ships, id), do: Enum.find(ships, &(&1.id == id))

  defp reader(%{principal: {:human, account}}), do: account.id
  defp reader(_access_context), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="harbour"
      class="harbour-sea__harbour"
      phx-hook="HarbourSea"
      phx-mounted={JS.ignore_attributes(["data-harbour-ready"])}
      data-harbour-crew={HarbourCrew.on_sea(drawn(@fleets, @public, @crew, @own, @access_context))}
      data-harbour-districts={is_binary(@shown) && HarbourCrew.districts(@shown)}
      aria-hidden="true"
    >
      <div id="harbour-stage" class="harbour-sea__stage" phx-update="ignore" data-harbour-stage>
        <canvas id="harbour-canvas" data-harbour-canvas></canvas>
        <span class="harbour-sea__tag" data-harbour-tag hidden></span>
      </div>
    </div>
    <nav :if={is_binary(@shown)} id="sea-bar" class="harbour-sea__bar" aria-label="The city">
      <button
        id="sea-return"
        type="button"
        class="harbour-sea__return"
        title="Bring the page back"
        phx-click={land()}
      >
        Keyfleet {Fleets.name(@shown)}
      </button>
      <.link
        id="sea-chat"
        class="rg-button rg-button--secondary"
        navigate={KeyLinks.hall_path(@shown)}
      >
        Chat
      </.link>
      <.link
        id="sea-workspace"
        class="rg-button rg-button--secondary"
        navigate={Fleets.path(@shown) <> "/workspace"}
      >
        Workspace
      </.link>
    </nav>
    <.agent_card
      :if={ship = @agent && ship(drawn(@fleets, @public, @crew, @own, @access_context), @agent)}
      ship={ship}
    />
    """
  end

  @doc """
  The button beside a fleet's name that lifts the page away to show the city,
  handing focus to the bar's first button, which brings it back (`land/0`). A
  press on the margin around the fleet's panel does the same
  (`assets/js/hooks/harbour_sea.ts`).

  The page is lifted while the body has `data-sea-lifted`. An attribute is set
  at once, where a class waits for the next frame, so the button that takes
  focus is already shown when it is asked to.
  """
  def lift(assigns) do
    ~H"""
    <button
      id="sea-lift"
      type="button"
      class="harbour-sea__lift"
      aria-controls="app-shell"
      aria-label="Show the city"
      title="Show the city"
      phx-click={JS.set_attribute({"data-sea-lifted", ""}, to: "body") |> JS.focus(to: "#sea-return")}
    >
      <svg viewBox="0 0 20 18" fill="currentColor" aria-hidden="true">
        <rect :for={{x, y, w, h} <- city_skyline()} x={x} y={y} width={w} height={h} />
        <rect class="harbour-sea__lift-flag" x="7" y="0" width="2" height="2" />
      </svg>
    </button>
    """
  end

  @doc "Brings the lifted page back, with focus on the button that lifted it."
  def land, do: JS.remove_attribute("data-sea-lifted", to: "body") |> JS.focus(to: "#sea-lift")

  # The lift button's picture, drawn in blocks like the Regents crown: four
  # towers of a skyline. Each tower is {x, y, width, height}; the beacon on the
  # tallest is drawn apart, in Tangerine.
  defp city_skyline do
    [
      {1, 9, 4, 9},
      {6, 3, 4, 15},
      {11, 6, 3, 12},
      {15, 11, 4, 7}
    ]
  end

  attr :ship, :map, required: true

  @doc """
  A ship's card: its name and Key, the address of its holder to copy and how
  many Keys they hold, their Keys' last few actions, and the Key's page. It
  opens as it is rendered and closes with its X, Escape or a new page.
  """
  def agent_card(assigns) do
    ~H"""
    <Regent.Structure.dialog
      id="harbour-agent"
      class="harbour-card"
      phx-hook="ModalDialog"
      phx-mounted={JS.ignore_attributes(["open", "style"])}
      data-close-event="close_agent"
      data-shown={@ship.id}
      aria-labelledby="harbour-agent-title"
    >
      <header class="harbour-card__head">
        <span class="harbour-card__sail" style={"--sail: #{@ship.color}"}></span>
        <div>
          <h2 id="harbour-agent-title" tabindex="-1" data-modal-title>{@ship.name}</h2>
          <p>{@ship.key}</p>
        </div>
        <form method="dialog">
          <button type="submit" class="harbour-card__close" aria-label="Close">
            <Regent.Icons.icon name="x" />
          </button>
        </form>
      </header>
      <p :if={@ship.owner} id="harbour-agent-owner" class="harbour-card__owner">
        <span>{Regents.Account.PublicIdentity.label(%{wallet_address: @ship.owner})}</span>
        <Regent.Primitives.copy_icon
          id="harbour-agent-owner-copy"
          text={@ship.owner}
          label="Copy the holder’s address"
        />
        <span :if={@ship.owned} class="harbour-card__owned">{keys_owned(@ship.owned)}</span>
      </p>
      <ol class="harbour-card__actions" aria-label="Recent actions">
        <li :for={{action, i} <- Enum.with_index(@ship.actions)}>
          <span>{action.text}</span>
          <RegentsWeb.Keyfleet.Time.local
            id={"harbour-agent-action-#{i}-at"}
            at={action.at}
            as={:moment}
          />
        </li>
      </ol>
      <.link class="harbour-card__key" navigate={KeyLinks.page_path(@ship.fleet_id, @ship.token_id)}>
        View <Regent.Icons.icon name="arrow-right" />
      </.link>
    </Regent.Structure.dialog>
    """
  end

  defp keys_owned(1), do: "1 Key owned"
  defp keys_owned(owned), do: "#{owned} Keys owned"
end
