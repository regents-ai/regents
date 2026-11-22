defmodule RegentsWeb.Keyfleet.ShellLive do
  @moduledoc """
  One LiveView holds the header, sidebar and account control across every in-app
  route and patches between them, so the frame never remounts on navigation.
  """

  use RegentsWeb, :live_view

  import RegentsWeb.Keyfleet.Components.LoadFailed
  import RegentsWeb.Keyfleet.Components.Shell

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Access
  alias Regents.Keyfleet.Atlas
  alias Regents.Keyfleet.Code
  alias Regents.Keyfleet.Dms
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Presets
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Muter

  alias RegentsWeb.Keyfleet.{
    AtlasLive,
    CodePassword,
    DmsLive,
    FleetLive,
    FleetNow,
    KeyMap,
    KeyProfileLive,
    KeysLive,
    PageRead,
    PollsLive,
    ProjectLive,
    ProjectPage,
    ProposalsLive,
    RoomsLive,
    SearchLive,
    SeasonPanel,
    SeasonsLive,
    SharedFigures,
    TreasuryLive,
    WorkspaceLive,
    WorldlineLive
  }

  alias Phoenix.Socket.Broadcast
  alias RegentsWeb.Keyfleet.Components.{AgentSetup, BuyKey, FleetPrompts, Reading, ScheduleCard}
  alias RegentsWeb.Keyfleet.{PublicDocuments, RouteCatalog}
  alias RegentsWeb.Live.Session
  alias RegentsWeb.NotFoundError

  # The events each area's page sends, which that area's module answers.
  @fleet_events ~w(activity_earlier open_pass_key keymap_ready keymap_pictures find_keys select_key validate_quote send_quote)
  @room_events ~w(mute_key unmute_key post_to_room)
  @key_profile_events ~w(post_to_key remove_from_wall close_key)
  @dm_events ~w(validate_dm send_dm dm_auto_delete dm_block dm_unblock dm_delete)
  @poll_events ~w(start_poll end_poll cast_vote)
  @search_events ~w(search search_more)
  @worldline_events ~w(worldline_older worldline_filter)
  @atlas_events ~w(atlas_older atlas_blocks_fleet atlas_blocks_things)
  @season_events ~w(season_pick season_lock season_more)
  @seasons_events ~w(seasons_more seasons_open)
  @sign_in_events ~w(open_notebooks get_code_password)
  @workspace_events ~w(pin unpin project_start project_archive project_take_over project_delete project_show project_describe publish_posts publish_item publish_page publish_commit withdraw_publication notebook_lock notebook_restore)

  # The routes that show a fleet's workspace and its votes.
  @workspace_routes [:workspace, :workspace_item, :code_commit, :code_history, :code_files]
  @proposals_routes [:proposals, :proposal, :treasury, :worldline]

  @press_failed "Something went wrong on our side. Refresh the page to see the latest, then try again."

  # Written by the Schedule card's hook (`assets/js/hooks/schedule_card.ts`).
  @schedule_cookie "keyfleet_schedule"

  @doc """
  What the page was rendered with, signed into its LiveView token: the site's
  own (`RegentsWeb.Live.Session.render_context/1`) and the fleets whose
  Schedule this browser put away, from the Schedule card's cookie as the page
  was requested, so a card shows from the first paint or not at all.
  """
  def render_context(conn),
    do:
      conn
      |> Session.render_context()
      |> Map.put("schedule_put_away", Map.get(conn.req_cookies, @schedule_cookie, ""))

  @impl true
  def mount(_params, %{"schedule_put_away" => schedule_put_away}, socket) do
    {:ok,
     socket
     |> follow_mutes()
     |> stream_configure(:posts, dom_id: &"post-#{&1.id}")
     |> stream(:posts, [])
     |> stream_configure(:fleet_who, dom_id: &"fleet-who-#{&1.id}")
     |> stream(:fleet_who, [])
     |> stream_configure(:dm_thread, dom_id: &"dm-#{&1.id}")
     |> stream(:dm_thread, [])
     |> stream_configure(:key_thread, dom_id: &"key-message-#{&1.id}")
     |> stream(:key_thread, [])
     |> stream_configure(:activity, dom_id: &FleetLive.activity_dom_id/1)
     |> stream(:activity, [])
     |> stream_configure(:worldline, dom_id: &WorldlineLive.dom_id/1)
     |> stream(:worldline, [])
     |> stream_configure(:atlas_things, dom_id: &AtlasLive.dom_id/1)
     |> stream(:atlas_things, [])
     |> stream_configure(:season_rows, dom_id: & &1.id)
     |> stream(:season_rows, [])
     |> stream_configure(:season_picks, dom_id: &"fleet-season-pick-#{&1.key}")
     |> stream(:season_picks, [])
     |> assign(
       route_spec: nil,
       schedule_put_away: ScheduleCard.put_away(schedule_put_away),
       shell_instance: System.unique_integer([:positive, :monotonic]),
       load_failed?: false,
       notebooks_notice: nil,
       code_password: nil,
       code_notice: nil,
       project_notice: nil,
       publish_notice: nil,
       project_page: nil,
       agents_topic: nil,
       fleet: nil,
       fleet_params: nil,
       fleet_place: :fleet,
       fleet_class: nil,
       keys_topics: [],
       activity: nil,
       activity_refresh: nil,
       key_profile: nil,
       key: nil,
       dms: nil,
       dms_topic: nil,
       dm_form: nil,
       dm_notice: nil,
       room: nil,
       room_notice: nil,
       room_topic: nil,
       workspace: nil,
       workspace_params: nil,
       workspace_topics: nil,
       workspace_refresh?: false,
       proposals: nil,
       proposals_params: nil,
       proposals_topic: nil,
       proposals_refresh?: false,
       treasury_reread: 0,
       treasury_resting: nil,
       polls: nil,
       polls_topics: [],
       polls_clock: nil,
       poll_form: nil,
       polls_notice: nil,
       search: nil,
       worldline: nil,
       atlas: nil,
       shared: %{},
       buy_key: nil,
       pass_note: nil,
       quotes: nil,
       season: nil,
       season_topics: [],
       seasons: nil
     )
     |> follow_agents(current_account(socket.assigns.access_context))}
  end

  # A page that couldn't be loaded may have started listening to what it was
  # loading before the read failed, so the next page is a whole new load.
  @impl true
  def handle_params(_params, uri, %{assigns: %{load_failed?: true}} = socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    {:noreply, redirect(socket, to: if(query, do: path <> "?" <> query, else: path))}
  end

  # A read the page can't do leaves the frame standing, with the page's place
  # saying it couldn't be loaded.
  def handle_params(params, uri, socket) do
    route_spec = route_spec(uri, params)
    params = name_fleet(params, route_spec)
    if beyond_supply?(params), do: raise(NotFoundError)

    case PageRead.run("app", fn -> load(socket, route_spec, params) end) do
      {:ok, loaded} ->
        loaded

      {:error, _failure} ->
        {:noreply,
         socket
         |> assign(route_spec: route_spec, load_failed?: true)
         |> assign(PublicDocuments.page(route_spec, params))}
    end
  end

  defp load(socket, route_spec, params) do
    if coming_soon_inside?(route_spec, params) do
      {:noreply, push_patch(socket, to: Fleets.path(route_spec.fleet_id), replace: true)}
    else
      # Going anywhere, back and forward included, leaves the room or
      # conversation on show read as far as it was shown.
      {:noreply,
       socket
       |> RoomsLive.leave()
       |> DmsLive.leave()
       |> assign(route_spec: route_spec)
       |> assign(PublicDocuments.page(route_spec, params))
       |> load_project(route_spec, params)
       |> read_class(params)
       |> follow_keys(keys_fleets(route_spec, params))
       |> load_fleet(route_spec, params)
       |> load_key_profile(socket.assigns)
       |> load_key(route_spec, params)
       |> load_dms(route_spec, params)
       |> load_room(route_spec, params)
       |> load_workspace(route_spec, params)
       |> load_proposals(route_spec, params)
       |> load_search(route_spec, params)
       |> PollsLive.read_polls(route_spec.route_id, params)
       |> WorldlineLive.read(route_spec.route_id, params)
       |> AtlasLive.read(route_spec.route_id, params)
       |> SeasonsLive.read(route_spec.route_id, params)}
    end
  end

  # Closing the page leaves the room or conversation on show read as far as it
  # was shown.
  @impl true
  def terminate(_reason, socket) do
    socket |> RoomsLive.leave() |> DmsLive.leave()
    :ok
  end

  # A fleet's page is asked for at the fleet's address, and read by its id.
  # The page at the address, as the router matched it: each part of the path
  # unescaped, as the router reads it. Of `params`, the page list reads only the
  # parts of the address its route names.
  defp route_spec(uri, params) do
    %URI{host: host, path: path} = URI.parse(uri)
    segments = for segment <- String.split(path, "/"), segment != "", do: URI.decode(segment)
    %{route: route} = Phoenix.Router.route_info(RegentsWeb.Router, "GET", segments, host)
    RouteCatalog.fetch!(route, params)
  end

  # A Key past its fleet's supply can never exist, so no page of it is found:
  # its own page, its messages, or a conversation with it.
  defp beyond_supply?(%{"fleet_id" => fleet_id} = params) do
    supply = Presets.max_supply(fleet_id)

    supply != nil and
      Enum.any?(
        [params["token_id"], params["other_token_id"]],
        &(&1 != nil and String.to_integer(&1) > supply)
      )
  end

  defp beyond_supply?(_params), do: false

  defp name_fleet(params, %{fleet_id: nil}), do: params
  defp name_fleet(params, %{fleet_id: fleet_id}), do: Map.put(params, "fleet_id", fleet_id)

  # A coming-soon fleet has only its own page: its workspace, proposals,
  # treasury, polls, seasons and search open with the fleet, and its hall
  # opens no room.
  defp coming_soon_inside?(%{route_id: route_id}, %{"fleet_id" => fleet_id})
       when route_id in [
              :workspace,
              :workspace_item,
              :code_commit,
              :code_history,
              :code_files,
              :project,
              :proposals,
              :proposal,
              :treasury,
              :polls,
              :poll,
              :seasons,
              :search,
              :worldline,
              :atlas
            ],
       do: Fleets.coming_soon?(fleet_id, Fleets.get_fleet!(fleet_id))

  defp coming_soon_inside?(_route_spec, _params), do: false

  # A press that can't be finished because the site's records can't be read
  # leaves the page as it was and says so, until a press goes through. Opening
  # the notebooks and getting a git password sign the person in elsewhere, so
  # they are answered as before.
  @impl true
  def handle_event(event, params, socket) when event in @sign_in_events,
    do: press(event, params, socket)

  def handle_event(event, params, socket) do
    case PageRead.run("app", fn -> press(event, params, socket) end) do
      {:ok, {:noreply, socket}} -> {:noreply, clear_flash(socket, :error)}
      {:ok, {:reply, reply, socket}} -> {:reply, reply, clear_flash(socket, :error)}
      {:error, _failure} -> {:noreply, put_flash(socket, :error, @press_failed)}
    end
  end

  # A notice the page can't answer because the site's records can't be read
  # leaves the page as it was; the next notice or visit reads again.
  @impl true
  def handle_info(message, socket) do
    case PageRead.run("app", fn -> notice(message, socket) end) do
      {:ok, answer} -> answer
      {:error, _failure} -> {:noreply, socket}
    end
  end

  # The fleet's notebooks open on their own address, signed in by a code that
  # works once, which Keyfleet's notebook page sends there
  # (`RegentsWeb.Keyfleet.NotebookOpenController`); only a holder of one of the
  # fleet's keys gets one.
  defp press("open_notebooks", _params, socket) do
    case human_actor(socket) do
      %Human{} ->
        {:noreply,
         redirect(socket, to: RouteCatalog.notebooks_path(socket.assigns.workspace.fleet_id))}

      nil ->
        {:noreply, assign(socket, notebooks_notice: "Sign in to open this fleet’s notebooks.")}
    end
  end

  # A git password for the fleet's code, for a holder of one of its keys; it
  # ends when this sign-in does.
  defp press("get_code_password", _params, socket) do
    with %Human{} = actor <- human_actor(socket),
         {:ok, %{password: password, expires_at: expires_at}} <-
           CodePassword.for_person(
             actor,
             socket.assigns.session_lease.lineage,
             socket.assigns.workspace.fleet_id
           ) do
      {:noreply,
       assign(socket,
         code_password: %{password: password, until: expires_at},
         code_notice: nil
       )}
    else
      nil ->
        {:noreply, assign(socket, code_notice: "Sign in to get a git password.")}

      {:error, :signed_out} ->
        {:noreply, assign(socket, code_notice: "Sign in to get a git password.")}

      {:error, :not_holder} ->
        {:noreply,
         assign(socket, code_notice: "Only holders of this fleet’s Keys can use its code.")}

      {:error, _error} ->
        {:noreply,
         assign(socket,
           code_notice: "A git password can’t be made right now. Try again in a minute."
         )}
    end
  end

  # "Buy Key" in the header and on a fleet page open
  # the "Buy Key" window for a fleet that sells its Keys, drawn from the
  # fleet's reading every page shares and drawn again as it changes.
  defp press("open_buy_key", %{"fleet" => fleet_id}, socket) do
    if fleet_id in Fleets.catalog_ids() and not Presets.given?(fleet_id) do
      {:noreply,
       socket
       |> SharedFigures.follow(:buy_key, [FleetNow.key(fleet_id)])
       |> assign(:buy_key, BuyKey.sale(fleet_id))}
    else
      {:noreply, socket}
    end
  end

  defp press("close_buy_key", _params, socket),
    do: {:noreply, socket |> SharedFigures.follow(:buy_key, []) |> assign(:buy_key, nil)}

  # The browser's Schedule cards put away, as its cookie says now: a fleet's
  # Schedule just put away, or one put away since the page was requested
  # (`assets/js/hooks/schedule_card.ts`).
  defp press("schedule_put_away", %{"put_away" => cookie}, socket),
    do: {:noreply, assign(socket, :schedule_put_away, ScheduleCard.put_away(cookie))}

  defp press(event, params, socket) when event in @workspace_events,
    do: WorkspaceLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @room_events,
    do: RoomsLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @key_profile_events,
    do: KeyProfileLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @fleet_events,
    do: FleetLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @dm_events,
    do: DmsLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @poll_events,
    do: PollsLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @search_events,
    do: SearchLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @worldline_events,
    do: WorldlineLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @atlas_events,
    do: AtlasLive.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @season_events,
    do: SeasonPanel.handle_event(event, params, socket)

  defp press(event, params, socket) when event in @seasons_events,
    do: SeasonsLive.handle_event(event, params, socket)

  # The Treasury's refresh, once every 30 seconds for each person: by
  # account when signed in, by visit when not.
  defp press("refresh_treasury", _params, socket) do
    who =
      case current_account(socket.assigns.access_context) do
        nil -> {:visit, socket.id}
        account -> {:account, account.id}
      end

    {:noreply, ProposalsLive.refresh_treasury(socket, who)}
  end

  # A press no page sends changes nothing.
  defp press(_event, _params, socket), do: {:noreply, socket}

  # The Treasury's refresh may be pressed again, whatever the page shows now.
  defp notice({:treasury_refresh_ready, rest}, socket),
    do: {:noreply, ProposalsLive.refresh_ready(socket, rest)}

  # A page that couldn't be loaded shows nothing else that a notice could
  # change; the header's balance still follows.
  defp notice(_message, %{assigns: %{load_failed?: true}} = socket), do: {:noreply, socket}

  # A new post of the room anyone reads, published whole on that room's own
  # topic (`Regents.Keyfleet.Rooms.Message.topic/2`), which the hall listens to while
  # the Public room is open in it, and shows as it came.
  defp notice(%Broadcast{topic: "keyfleet:public:room:" <> _} = notice, socket),
    do: RoomsLive.handle_info(notice, socket)

  # A notice that the open room has taken a post it is not showing yet is only a
  # nudge to look again. The new posts are read back from the room itself, and
  # a room shown as for keys only looks again at whether the reader may read
  # it; the place the notice names is never shown. The Public room's posts come whole
  # just before their head, so a page of the Public room is level with the head when
  # it arrives and reads nothing; only a post whose notice was lost leaves it
  # behind. A member's hall reads its feed, hidden under the room, again.
  defp notice(
         %Broadcast{event: "room_head", payload: %{room_id: room_id, seq: seq}},
         %{assigns: %{room: %{room_id: room_id, last_seq: last_seq}}} = socket
       )
       when seq > last_seq do
    socket = RoomsLive.show_new_posts(socket)
    {:noreply, FleetLive.refresh_activity_soon(socket, fleet_on_show(socket))}
  end

  # The page only hears about the rooms of the fleet it shows. The hall marks
  # the room in its list as having something new when a room is open, and a
  # member's hall reads its feed again.
  defp notice(%Broadcast{event: "room_head", payload: head}, socket) do
    socket = socket |> RoomsLive.note_head(head) |> WorldlineLive.heard(:posts)
    {:noreply, FleetLive.refresh_activity_soon(socket, fleet_on_show(socket))}
  end

  # The person's agents changed on any Regent site: paired, checked in,
  # corrected or unpaired. Pair on a fleet's page follows, and the agents'
  # states and shard presses on the person's own Key's page.
  defp notice(:agents_changed, socket),
    do:
      {:noreply,
       socket |> prompts_changed() |> agent_setup_changed() |> KeysLive.agents_changed()}

  defp notice(%Broadcast{event: event} = notice, socket)
       when event in ["dm_head", "dm_deleted"],
       do: DmsLive.handle_info(notice, socket)

  defp notice(%Broadcast{event: event} = notice, socket)
       when event in ["key_activity", "wall_removed"],
       do: KeyProfileLive.handle_info(notice, socket)

  defp notice(%Broadcast{event: "rooms_changed"} = notice, socket),
    do: RoomsLive.handle_info(notice, socket)

  # The Worldline on show reads the polls started a moment later.
  defp notice(%Broadcast{event: "polls_changed"}, %{assigns: %{worldline: %{}}} = socket),
    do: {:noreply, WorldlineLive.heard(socket, :polls)}

  defp notice(%Broadcast{event: event} = notice, socket)
       when event in ["poll_changed", "polls_changed"],
       do: PollsLive.handle_info(notice, socket)

  defp notice(:polls_tick = message, socket), do: PollsLive.handle_info(message, socket)

  # A turn of the fleet's seasons, or a pick locked for the one taking picks:
  # a member's "Season" panel reads what it changed.
  defp notice(%Broadcast{event: event} = notice, socket)
       when event in ["seasons_changed", "season_changed"],
       do: {:noreply, SeasonPanel.heard(socket, notice)}

  # A mute added or taken away hides or shows that key's posts in the room on
  # show and in the open key's thread.
  defp notice(
         %Broadcast{event: "mutes_changed", payload: %{fleet_id: fleet_id}} = notice,
         socket
       ) do
    {:noreply, socket} = RoomsLive.handle_info(notice, socket)
    {:noreply, KeyProfileLive.show_unmuted(socket, fleet_id)}
  end

  # Keys changed in a fleet. What the reader may read of the fleet in the
  # address is read again first, and the page moves to what that class hears.
  # The class read stands, with what it hears, when the page can't be read again.
  # The fleet's Worldline reads its Keys and shards again a moment later.
  defp notice({:keys_changed, fleet_id, token_ids}, socket) do
    socket =
      socket
      |> reread_class(fleet_id)
      |> prompts_changed()
      |> WorldlineLive.heard(fleet_id, :keys)

    case PageRead.run("app", fn -> keys_changed(socket, fleet_id, token_ids) end) do
      {:ok, answer} -> answer
      {:error, _failure} -> {:noreply, socket}
    end
  end

  # Keys in a fleet were marked present: one notice for each pass of the chain
  # reader that recorded any. Only what shows presence reads again: Mark
  # present on the fleet's page, when one of the Keys was the person's idle
  # Key, and on the person's own Key's page their agents' states; and the
  # fleet's Worldline, a moment later.
  defp notice({:keys_present, fleet_id, token_ids}, socket) do
    socket = WorldlineLive.heard(socket, fleet_id, :present)

    case socket.assigns do
      %{fleet: %{fleet_id: ^fleet_id}} ->
        send_update(FleetPrompts, id: "fleet-prompts", present: token_ids)
        {:noreply, socket}

      %{key: %{fleet_id: ^fleet_id}} ->
        {:noreply, agent_setup_changed(socket)}

      _other ->
        {:noreply, socket}
    end
  end

  # A notice that the open fleet's workspace has moved past what the page last
  # read is only a nudge to read it again, once, a moment later: the notices
  # that come in the meantime are answered by that one read.
  defp notice(
         {:graph_head, fleet_id, run_id, watermark},
         %{assigns: %{workspace: %{fleet_id: fleet_id, seen: seen}}} = socket
       ),
       do: {:noreply, WorkspaceLive.refresh_soon(socket, seen, run_id, watermark)}

  defp notice({:graph_head, fleet_id, _run_id, _watermark}, socket),
    do:
      {:noreply,
       socket
       |> WorldlineLive.heard(:changes)
       |> AtlasLive.heard(fleet_id)
       |> FleetLive.refresh_activity_soon(fleet_id)}

  # The fleet's Atlas counted work the workspace's own notices don't tell of:
  # its history, or its notebooks as their hub was read.
  defp notice({:atlas_changed, fleet_id}, socket),
    do: {:noreply, AtlasLive.heard(socket, fleet_id)}

  # What anyone hears of the workspace: the fleet's activity has a new change
  # of it to show.
  defp notice(
         {:graph_notable, fleet_id},
         %{assigns: %{workspace: %{fleet_id: fleet_id}}} = socket
       ),
       do: {:noreply, WorkspaceLive.refresh_later(socket)}

  defp notice({:graph_notable, fleet_id}, socket),
    do: {:noreply, FleetLive.refresh_activity_soon(socket, fleet_id)}

  defp notice(:refresh_workspace = message, socket),
    do: WorkspaceLive.handle_info(message, socket)

  # Changes sent to the open fleet's code show in its workspace a moment later.
  defp notice(
         {:code_pushed, fleet_id},
         %{assigns: %{workspace: %{fleet_id: fleet_id}}} = socket
       ),
       do: {:noreply, WorkspaceLive.refresh_later(socket)}

  defp notice({:code_pushed, _fleet_id}, socket),
    do: {:noreply, WorldlineLive.heard(socket, :pushes)}

  # A notice that the open fleet's proposal records or balances changed is a
  # nudge to read its page again, once, a moment later, like the workspace's.
  defp notice(
         {notice, fleet_id},
         %{assigns: %{proposals: %{fleet_id: fleet_id}}} = socket
       )
       when notice in [:proposals_changed, :balances_changed],
       do: {:noreply, ProposalsLive.refresh_soon(socket)}

  # Votes recorded in the fleet move the open key's two vote figures.
  defp notice(
         {:proposals_changed, fleet_id},
         %{assigns: %{key_profile: %{fleet_id: fleet_id, issued?: true}}} = socket
       ) do
    {:noreply,
     socket
     |> KeyProfileLive.refresh_votes()
     |> WorldlineLive.heard(:proposals)
     |> FleetLive.refresh_activity_soon(fleet_id)}
  end

  defp notice({:proposals_changed, fleet_id}, socket),
    do:
      {:noreply,
       socket |> WorldlineLive.heard(:proposals) |> FleetLive.refresh_activity_soon(fleet_id)}

  # A new reading of the fleet's balances, every five minutes, may carry
  # income, so the open key's rewards are read again with it.
  defp notice(
         {:balances_changed, fleet_id},
         %{assigns: %{key_profile: %{fleet_id: fleet_id}}} = socket
       ),
       do: {:noreply, KeyProfileLive.refresh_rewards(socket)}

  defp notice({:balances_changed, _fleet_id}, socket), do: {:noreply, socket}

  defp notice(:refresh_proposals = message, socket),
    do: ProposalsLive.handle_info(message, socket)

  defp notice({:onchain_landed, fleet_id}, socket),
    do: {:noreply, socket |> prompts_changed() |> ProposalsLive.onchain_landed(fleet_id)}

  # A reading every page shares has changed: the part of the page showing it
  # draws it again.
  defp notice({:shared_reading, key}, socket),
    do:
      {:noreply,
       socket
       |> FleetLive.shared_changed(key)
       |> KeyProfileLive.shared_changed(key)
       |> ProposalsLive.shared_changed(key)
       |> buy_key_changed(key)}

  defp notice({:refresh_activity, _fleet_id} = message, socket),
    do: FleetLive.handle_info(message, socket)

  defp notice(:refresh_worldline = message, socket),
    do: WorldlineLive.handle_info(message, socket)

  defp notice(:refresh_atlas = message, socket),
    do: AtlasLive.handle_info(message, socket)

  defp buy_key_changed(
         %{assigns: %{buy_key: %{id: fleet_id}}} = socket,
         {:keyfleet_fleet_now, fleet_id}
       ),
       do: assign(socket, :buy_key, BuyKey.sale(fleet_id))

  defp buy_key_changed(socket, _key), do: socket

  @impl true
  def handle_async(:rewards, result, socket),
    do: KeyProfileLive.handle_async(:rewards, result, socket)

  def handle_async(:slice, result, socket),
    do: KeyProfileLive.handle_async(:slice, result, socket)

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      account_control={@account_control}
      shell_instance={@shell_instance}
    >
      <:buy_key :if={@buy_key}>
        <BuyKey.window sale={@buy_key} actor={actor(@access_context)} lease={@session_lease} />
      </:buy_key>
      <:content :if={@load_failed?}>
        <article id="page-load-failed" class="fleet-page">
          <section class="fleet-panel">
            <h1 tabindex="-1">Keyfleet</h1>
            <.load_failed />
          </section>
        </article>
      </:content>
      <:content :if={!@load_failed?}>
        <Reading.page
          :if={@route_spec.route_id in Reading.pages()}
          path={@route_spec.destination}
        />

        <ProjectLive.page
          :if={@route_spec.route_id == :project}
          project={@project_page}
          workspace?={reads_workspace?(@fleet_class)}
        />

        <FleetLive.page
          :if={fleet_place(@route_spec.route_id)}
          place={fleet_place(@route_spec.route_id)}
          fleet={@fleet}
          actor={actor(@access_context)}
          account={current_account(@access_context)}
          lease={@session_lease}
          params={@fleet_params}
          profile={@key_profile}
          thread={@streams.key_thread}
          activity={@streams.activity}
          who={@streams.fleet_who}
          now={FleetLive.now_shown(@activity)}
          pass_note={@pass_note}
          schedule_put_away={@schedule_put_away}
          quotes={@quotes}
          room={@room}
          posts={@streams.posts}
          room_notice={@room_notice}
          season={@season}
          season_picks={@streams.season_picks}
        >
          <WorkspaceLive.board
            :if={@route_spec.route_id == :workspace}
            board={@workspace}
            notebooks_notice={@notebooks_notice}
            code_password={@code_password}
            code_notice={@code_notice}
            project_notice={@project_notice}
            publish_notice={@publish_notice}
            signed_out?={is_nil(actor(@access_context))}
          />
          <WorkspaceLive.item
            :if={@route_spec.route_id == :workspace_item}
            item={@workspace}
            publish_notice={@publish_notice}
            signed_out?={is_nil(actor(@access_context))}
          />
          <WorkspaceLive.commit
            :if={@route_spec.route_id == :code_commit}
            commit={@workspace}
            publish_notice={@publish_notice}
            signed_out?={is_nil(actor(@access_context))}
          />
          <WorkspaceLive.history
            :if={@route_spec.route_id == :code_history}
            history={@workspace}
            signed_out?={is_nil(actor(@access_context))}
          />
          <WorkspaceLive.files
            :if={@route_spec.route_id == :code_files}
            files={@workspace}
            signed_out?={is_nil(actor(@access_context))}
          />
          <TreasuryLive.page
            :if={@route_spec.route_id == :treasury}
            page={@proposals}
            actor={actor(@access_context)}
            lease={@session_lease}
            reread={@treasury_reread}
            resting?={@treasury_resting != nil}
          />
          <SearchLive.results :if={@route_spec.route_id == :search} search={@search} />
          <WorldlineLive.page
            :if={@route_spec.route_id == :worldline}
            worldline={@worldline}
            events={@streams.worldline}
          />
          <AtlasLive.page
            :if={@route_spec.route_id == :atlas}
            atlas={@atlas}
            things={@streams.atlas_things}
            signed_out?={is_nil(actor(@access_context))}
          />
          <SeasonsLive.page
            :if={@route_spec.route_id == :seasons}
            seasons={@seasons}
            rows={@streams.season_rows}
          />
          <ProposalsLive.list
            :if={@route_spec.route_id == :proposals}
            page={@proposals}
            actor={actor(@access_context)}
            lease={@session_lease}
          />
          <ProposalsLive.detail
            :if={@route_spec.route_id == :proposal}
            page={@proposals}
            actor={actor(@access_context)}
            lease={@session_lease}
          />
        </FleetLive.page>

        <KeysLive.page
          :if={@route_spec.route_id == :keys}
          key={@key}
          actor={actor(@access_context)}
          lease={@session_lease}
        />

        <DmsLive.inbox :if={@route_spec.route_id == :dms} dms={@dms} />

        <DmsLive.conversation
          :if={@route_spec.route_id == :dm}
          dms={@dms}
          messages={@streams.dm_thread}
          form={@dm_form}
          notice={@dm_notice}
        />

        <PollsLive.list
          :if={@route_spec.route_id == :polls}
          page={@polls}
          form={@poll_form}
          notice={@polls_notice}
        />
        <PollsLive.detail
          :if={@route_spec.route_id == :poll}
          page={@polls}
          notice={@polls_notice}
        />
      </:content>
    </.shell>
    """
  end

  # The fleet's places drawn inside its page, under its bar: the page's own
  # views, its Treasury, its Workspace, its search, its Worldline, its Atlas
  # and its record of seasons.
  defp fleet_place(:fleet), do: :fleet
  defp fleet_place(:treasury), do: :treasury
  defp fleet_place(:search), do: :search
  defp fleet_place(:worldline), do: :worldline
  defp fleet_place(:atlas), do: :atlas
  defp fleet_place(:seasons), do: :seasons
  defp fleet_place(route_id) when route_id in [:proposals, :proposal], do: :proposals

  defp fleet_place(route_id)
       when route_id in [:workspace, :workspace_item, :code_commit, :code_history, :code_files],
       do: :workspace

  defp fleet_place(_route_id), do: nil

  defp current_account(%{principal: {:human, account}}), do: account
  defp current_account(_access_context), do: nil

  # Whether the reader may open the fleet's workspace, as its class was last
  # read: only then does a project's page link every title, "See all" and
  # "Open in the workspace" there.
  defp reads_workspace?(%{class: class}), do: Access.enough?(class, :read, :workspace)
  defp reads_workspace?(nil), do: false

  # A project's page is read once, as it opens, and carries its title and,
  # once its Key describes it, its description.
  defp load_project(socket, %{route_id: :project}, %{
         "fleet_id" => fleet_id,
         "project" => name
       }) do
    project = ProjectPage.read(fleet_id, name)

    assign(socket,
      project_page: project,
      page_title: project.title <> " · " <> project.fleet_name,
      page_description: project.description || socket.assigns.page_description
    )
  end

  defp load_project(socket, _route_spec, _params), do: assign(socket, :project_page, nil)

  # The page starts listening for changed keys before it reads, so a change
  # that lands while it loads still reaches it. The map is told when the key
  # chosen changes under it: back or forward, or another fleet's page.
  defp load_fleet(socket, %{route_id: route_id}, %{"fleet_id" => fleet_id} = params)
       when route_id in [
              :fleet,
              :treasury,
              :workspace,
              :workspace_item,
              :code_commit,
              :code_history,
              :code_files,
              :proposals,
              :proposal,
              :search,
              :worldline,
              :atlas,
              :seasons
            ] do
    shown = socket.assigns.fleet

    socket
    |> listen_to(rooms_heard(socket, params, fleet_id))
    |> follow_workspace(workspace_heard(socket, route_id, fleet_id))
    |> follow_proposals(proposals_heard(socket, route_id, params, fleet_id))
    |> FleetLive.read_fleet(params, fleet_place(route_id))
    |> FleetLive.tell_map_chosen(shown)
  end

  defp load_fleet(socket, _route_spec, _params),
    do:
      socket
      |> SharedFigures.follow(:fleet, [])
      |> SeasonPanel.leave()
      |> assign(
        fleet: nil,
        fleet_params: nil,
        fleet_place: :fleet,
        quotes: nil,
        activity: nil,
        activity_refresh: nil
      )
      |> stream(:fleet_who, [], reset: true)
      |> stream(:activity, [], reset: true)

  # What a page of the fleet hears of its rooms, workspace and votes besides
  # its Keys: a page showing one of them hears it (a room open in the hall
  # hears the rooms), and a member's page hears
  # them all, since a member's feed is read again on each. Anyone else's
  # hall is drawn from the fleet's reading every such page shares
  # (`RegentsWeb.Keyfleet.FleetNow`), which hears them once for all of those pages,
  # so their page hears only what a Key open over it shows: its wall, in
  # the rooms, and its votes and rewards. The Worldline hears the rooms and
  # votes its reader reads. Each gives the fleet heard, or nil.
  defp rooms_heard(socket, params, fleet_id) do
    if fleet_id &&
         (member?(socket, fleet_id) or socket.assigns.route_spec.route_id == :worldline or
            Map.has_key?(params, "key") or Map.has_key?(params, "room")),
       do: fleet_id
  end

  defp workspace_heard(socket, route_id, fleet_id),
    do: if(fleet_id && (route_id in @workspace_routes or member?(socket, fleet_id)), do: fleet_id)

  defp proposals_heard(socket, route_id, params, fleet_id) do
    if fleet_id &&
         (route_id in @proposals_routes or member?(socket, fleet_id) or
            Map.has_key?(params, "key")),
       do: fleet_id
  end

  # A fleet's page holds Pair and Mark present (`FleetPrompts`), which read
  # again when the person's agents, the fleet's Keys or a step sent from the
  # page change.
  defp prompts_changed(%{assigns: %{fleet: %{fleet_id: _}}} = socket) do
    send_update(FleetPrompts, id: "fleet-prompts", changed: true)
    socket
  end

  defp prompts_changed(socket), do: socket

  # The person's own Key's page holds their agents' states (`AgentSetup`),
  # which read again when an agent checks in or Keys are marked present.
  defp agent_setup_changed(%{assigns: %{key: %{owner?: true}}} = socket) do
    send_update(AgentSetup, id: "key-agent-setup", changed: true)
    socket
  end

  defp agent_setup_changed(socket), do: socket

  # Keys changed in the fleet on show: its sales figures and the key on offer
  # are read again, and its Member List when it is on show (the agents here
  # come from the readings every page shares, `Regents.Keyfleet.Agents.Here`), the
  # open key's profile when the key or one of its holder's changed, and the
  # map is told the changed keys' marks, or told to load again when too many
  # changed to list, and who may read the room open in the hall is read
  # afresh. A hall drawn from the fleet's reading reads only the
  # reader's own Keys and profile; its figures come with the reading, and
  # it shows no map, which reads its Keys afresh when it is next shown.
  defp keys_changed(
         %{assigns: %{fleet: %{fleet_id: fleet_id, deployed?: true}}} = socket,
         fleet_id,
         token_ids
       ) do
    socket =
      socket
      |> FleetLive.refresh_sales()
      |> FleetLive.refresh_members()
      |> KeyProfileLive.refresh_key_profile(token_ids)
      |> FleetLive.refresh_activity_soon(fleet_id)
      |> workspace_standing_changed(fleet_id)
      |> RoomsLive.recheck_standing()

    if FleetLive.from_reading?(socket),
      do: {:noreply, socket},
      else: tell_map_changed(socket, fleet_id, token_ids)
  end

  # Keys changed in the fleet whose polls are on show: who takes part as which
  # Key is read afresh.
  defp keys_changed(%{assigns: %{polls: %{fleet_id: fleet_id}}} = socket, fleet_id, _token_ids),
    do: {:noreply, PollsLive.refresh(socket)}

  # Keys changed in a fleet not yet on sale whose room is open in its hall:
  # who may read it is read afresh.
  defp keys_changed(%{assigns: %{room: %{fleet_id: fleet_id}}} = socket, fleet_id, _token_ids),
    do: {:noreply, RoomsLive.recheck_standing(socket)}

  # Keys changed in the fleet whose workspace is on show: whether its reader
  # may read it is read afresh.
  defp keys_changed(
         %{assigns: %{workspace: %{fleet_id: fleet_id}}} = socket,
         fleet_id,
         _token_ids
       ),
       do: {:noreply, WorkspaceLive.refresh_later(socket)}

  # A notice for the key page on show, or for a fleet the page has since
  # left, or one not yet on sale.
  defp keys_changed(socket, fleet_id, token_ids),
    do:
      {:noreply,
       socket
       |> KeysLive.refresh_key(fleet_id, token_ids)
       |> FleetLive.refresh_activity_soon(fleet_id)}

  defp tell_map_changed(socket, fleet_id, token_ids) do
    progress = socket.assigns.fleet.progress

    case KeyMap.change(fleet_id, progress, token_ids, human_actor(socket)) do
      :reset -> {:noreply, push_event(socket, "keymap:reset", %{})}
      {:patch, patch} -> {:noreply, push_event(socket, "keymap:patch", patch)}
    end
  end

  # Whether the reader may read the fleet's workspace on show is read afresh.
  defp workspace_standing_changed(
         %{assigns: %{workspace: %{fleet_id: fleet_id}}} = socket,
         fleet_id
       ),
       do: WorkspaceLive.refresh_later(socket)

  defp workspace_standing_changed(socket, _fleet_id), do: socket

  # What the reader may read of the fleet in the address
  # (`Regents.Keyfleet.Access.class/2`), read on every visit before the page listens
  # to anything of the fleet.
  defp read_class(socket, %{"fleet_id" => fleet_id}),
    do: assign(socket, :fleet_class, fleet_class(socket, fleet_id))

  defp read_class(socket, _params), do: assign(socket, :fleet_class, nil)

  defp fleet_class(socket, fleet_id),
    do: %{fleet_id: fleet_id, class: Access.class(human_actor(socket), fleet_id)}

  @doc """
  The class of `fleet_id`, the fleet in the address, read again. With a new
  one the page leaves what the old one heard of the fleet's rooms, workspace
  and votes for what the new one hears, and the fleet's hall moves to how the
  new one sees it.
  """
  def reread_class(%{assigns: %{fleet_class: %{fleet_id: fleet_id} = was}} = socket, fleet_id) do
    case fleet_class(socket, fleet_id) do
      ^was ->
        socket

      now ->
        socket
        |> assign(:fleet_class, now)
        |> hear_as_class()
        |> FleetLive.class_changed(fleet_id)
        |> KeyProfileLive.class_changed(fleet_id)
        |> WorldlineLive.class_changed(fleet_id)
        |> AtlasLive.class_changed(fleet_id)
    end
  end

  def reread_class(socket, _fleet_id), do: socket

  # A page of the fleet hears what `rooms_heard/3` and the rest say its
  # class hears, each class on its own topic.
  defp hear_as_class(%{assigns: %{route_spec: %{route_id: route_id}}} = socket) do
    on_show = fleet_on_show(socket)
    params = socket.assigns.fleet_params || %{}

    socket
    |> listen_to(rooms_heard(socket, params, on_show))
    |> follow_workspace(workspace_heard(socket, route_id, on_show))
    |> follow_proposals(proposals_heard(socket, route_id, params, on_show))
  end

  # The class of the fleet in the address, as it was last read.
  defp class(%{assigns: %{fleet_class: %{fleet_id: fleet_id, class: class}}}, fleet_id),
    do: class

  @doc """
  The options that read `fleet_id`, the fleet in the address, as the reader
  with the class last read, so its policies don't read the class again.
  """
  def reads_as(socket, fleet_id) do
    actor = human_actor(socket)
    [actor: actor, context: Access.context(actor, fleet_id, class(socket, fleet_id))]
  end

  @doc "Whether the reader is a member of `fleet_id`, the fleet in the address, as last read."
  def member?(%{assigns: %{fleet_class: %{fleet_id: fleet_id, class: :member}}}, fleet_id),
    do: true

  def member?(_socket, _fleet_id), do: false

  @doc """
  Whether the reader may read `component` (`Regents.Keyfleet.Access`) of `fleet_id`,
  the fleet in the address, as last read.
  """
  def may_read?(
        %{assigns: %{fleet_class: %{fleet_id: fleet_id, class: class}}},
        fleet_id,
        component
      ),
      do: Access.enough?(class, :read, component)

  def may_read?(_socket, _fleet_id, _component), do: false

  # The fleet whose keys the page on show follows: the fleet's own page, one
  # of its keys' pages, its workspace, or its polls.
  defp keys_fleets(%{route_id: route_id}, %{"fleet_id" => fleet_id})
       when route_id in [
              :fleet,
              :keys,
              :workspace,
              :workspace_item,
              :code_commit,
              :code_history,
              :code_files,
              :polls,
              :poll
            ],
       do: [fleet_id]

  defp keys_fleets(_route_spec, _params), do: []

  # A person signed in hears when their own mutes change, on any of their
  # pages, for as long as the page is open.
  defp follow_mutes(socket) do
    muter = Muter.of(human_actor(socket))
    if connected?(socket) and muter != nil, do: start_listening(Muter.topic(muter))
    socket
  end

  # One subscription to the keys of each fleet on show, dropped on the way out.
  defp follow_keys(socket, fleet_ids) do
    topics = Enum.map(fleet_ids, &Keys.topic/1)

    if connected?(socket) and topics != socket.assigns.keys_topics do
      Enum.each(socket.assigns.keys_topics, &stop_listening/1)
      Enum.each(topics, &start_listening/1)
      assign(socket, :keys_topics, topics)
    else
      socket
    end
  end

  # The key named in the address opens over its fleet's page. The fleet's page
  # has already started listening to the fleet's rooms and votes, so a message
  # that lands while the key loads still reaches it.
  defp load_key_profile(%{assigns: %{fleet: %{chosen_key: token_id} = fleet}} = socket, before)
       when is_integer(token_id),
       do: KeyProfileLive.read_key_profile(socket, fleet, token_id, before)

  defp load_key_profile(socket, _before),
    do:
      socket
      |> SharedFigures.follow(:key, [])
      |> assign(:key_profile, nil)
      |> stream(:key_thread, [], reset: true)

  defp load_key(socket, %{route_id: :keys}, %{"fleet_id" => fleet_id, "token_id" => token_id}),
    do: assign(socket, :key, KeysLive.key_view(socket, fleet_id, String.to_integer(token_id)))

  defp load_key(socket, _route_spec, _params), do: assign(socket, :key, nil)

  # The page starts listening to the Key's messages before it reads them, so
  # one that lands while it loads still reaches it, and stops when it turns
  # out not to be the Key's holder.
  defp load_dms(socket, %{route_id: route_id}, %{"fleet_id" => fleet_id} = params)
       when route_id in [:dms, :dm] do
    token_id = String.to_integer(params["token_id"])
    other_token_id = params["other_token_id"] && String.to_integer(params["other_token_id"])

    socket =
      socket
      |> follow_dms(Dms.inbox_topic(fleet_id, token_id))
      |> DmsLive.read_dms(route_id, fleet_id, token_id, other_token_id)

    case socket.assigns.dms do
      %{holder?: true} -> socket
      _closed -> follow_dms(socket, nil)
    end
  end

  defp load_dms(socket, _route_spec, _params) do
    socket
    |> follow_dms(nil)
    |> assign(dms: nil, dm_form: nil, dm_notice: nil)
    |> stream(:dm_thread, [], reset: true)
  end

  # One subscription to the messages of the Key on show, dropped on the way out.
  defp follow_dms(socket, topic) do
    if connected?(socket) and topic != socket.assigns.dms_topic do
      stop_listening(socket.assigns.dms_topic)
      start_listening(topic)
      assign(socket, :dms_topic, topic)
    else
      socket
    end
  end

  # The room named in the address opens in the middle of its fleet's hall.
  # The fleet's page has already started listening to the fleet's rooms
  # (`rooms_heard/3`), so a post that lands while it loads still reaches it;
  # a notice for a post it already read is passed over.
  defp load_room(
         %{assigns: %{fleet: %{fleet_id: fleet_id, coming_soon?: false}}} = socket,
         %{route_id: :fleet},
         %{"fleet_id" => fleet_id, "room" => slug} = params
       )
       when is_binary(slug) and not is_map_key(params, "view"),
       do: RoomsLive.read_room(socket, fleet_id, slug)

  # A fleet's page keeps listening to the fleet's rooms, as its reader's
  # class hears them (`rooms_heard/3`).
  defp load_room(socket, _route_spec, params) do
    socket
    |> listen_to(rooms_heard(socket, params, fleet_on_show(socket)))
    |> assign(room: nil, room_notice: nil)
  end

  defp fleet_on_show(%{assigns: %{fleet: %{fleet_id: fleet_id}}}), do: fleet_id
  defp fleet_on_show(_socket), do: nil

  # One subscription per fleet, taken up on the way into its rooms and dropped
  # on the way out, so a page only hears about the fleet it is showing, and of
  # that only what its reader's class hears.
  defp listen_to(socket, fleet_id) do
    topic = fleet_id && Rooms.topic(fleet_id, class(socket, fleet_id))

    if connected?(socket) and topic != socket.assigns.room_topic do
      stop_listening(socket.assigns.room_topic)
      start_listening(topic)
      assign(socket, :room_topic, topic)
    else
      socket
    end
  end

  defp stop_listening(nil), do: :ok
  defp stop_listening(topic), do: Phoenix.PubSub.unsubscribe(Regents.PubSub, topic)

  defp start_listening(nil), do: :ok
  defp start_listening(topic), do: Phoenix.PubSub.subscribe(Regents.PubSub, topic)

  # The page starts listening before it reads, so a change that lands while it
  # loads still reaches it. Each visit, reconnection included, reads afresh.
  defp load_workspace(socket, %{route_id: route_id}, %{"fleet_id" => fleet_id} = params)
       when route_id in [:workspace, :workspace_item, :code_commit, :code_history, :code_files] do
    socket
    |> follow_workspace(fleet_id)
    |> assign(
      workspace_params: params,
      notebooks_notice: nil,
      code_password: nil,
      code_notice: nil,
      project_notice: nil,
      publish_notice: nil
    )
    |> WorkspaceLive.read_workspace()
  end

  # A fleet's page keeps hearing about the fleet's workspace, as its
  # reader's class hears it (`workspace_heard/3`).
  defp load_workspace(socket, %{route_id: route_id}, _params) do
    socket
    |> follow_workspace(workspace_heard(socket, route_id, fleet_on_show(socket)))
    |> assign(workspace: nil, workspace_params: nil)
  end

  # The workspace as the reader's class hears it, and changes sent to the
  # fleet's code for whoever reads that.
  defp follow_workspace(socket, fleet_id) do
    topics = if fleet_id, do: workspace_topics(fleet_id, class(socket, fleet_id)), else: []

    if connected?(socket) and topics != socket.assigns.workspace_topics do
      Enum.each(List.wrap(socket.assigns.workspace_topics), &stop_listening/1)
      Enum.each(topics, &start_listening/1)
      assign(socket, :workspace_topics, topics)
    else
      socket
    end
  end

  defp workspace_topics(fleet_id, class) do
    code = if Access.enough?(class, :read, :code), do: [Code.topic(fleet_id)], else: []
    atlas = if Access.enough?(class, :read, :workspace), do: [Atlas.topic(fleet_id)], else: []
    [Graph.topic(fleet_id, class) | code ++ atlas]
  end

  # The page starts listening before it reads, so votes recorded while it
  # loads still reach it. Each visit, reconnection included, reads afresh.
  defp load_proposals(socket, %{route_id: route_id}, %{"fleet_id" => fleet_id} = params)
       when route_id in [:proposals, :proposal, :treasury] do
    socket = assign(socket, :proposals_params, params)

    socket
    |> follow_proposals(if ProposalsLive.for_visit?(socket), do: fleet_id)
    |> ProposalsLive.read_proposals()
  end

  # A fleet's page keeps hearing about the fleet's votes, as its reader's
  # class hears them (`proposals_heard/4`).
  defp load_proposals(socket, %{route_id: route_id}, params) do
    socket
    |> follow_proposals(proposals_heard(socket, route_id, params, fleet_on_show(socket)))
    |> SharedFigures.follow(:proposals, [])
    |> assign(proposals: nil, proposals_params: nil)
  end

  # The search page reads its first page of matches as it opens.
  defp load_search(socket, %{route_id: :search}, params),
    do: SearchLive.read(socket, params, actor(socket.assigns.access_context))

  defp load_search(socket, _route_spec, _params), do: assign(socket, :search, nil)

  defp follow_proposals(socket, fleet_id) do
    topic = fleet_id && Proposals.topic(fleet_id)

    if connected?(socket) and topic != socket.assigns.proposals_topic do
      stop_listening(socket.assigns.proposals_topic)
      start_listening(topic)
      assign(socket, :proposals_topic, topic)
    else
      socket
    end
  end

  # Hears when the person's agents change, for every page that shows them.
  defp follow_agents(%{assigns: %{agents_topic: nil}} = socket, %{privy_user_id: person}) do
    if connected?(socket) do
      topic = RegentAgents.topic(person)
      :ok = Phoenix.PubSub.subscribe(Regents.PubSub, topic)
      assign(socket, :agents_topic, topic)
    else
      socket
    end
  end

  defp follow_agents(socket, _account), do: socket

  @doc "The signed-in person the page acts for, or nil; the area pages act as them too."
  def human_actor(%{assigns: %{access_context: access_context}}), do: actor(access_context)
  def human_actor(_socket), do: nil

  defp actor(%{principal: {:human, account}}), do: Human.for_account(account)
  defp actor(_access_context), do: nil
end
