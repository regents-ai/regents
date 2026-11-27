defmodule RegentsWeb.Keyfleet.WorldlineLive do
  @moduledoc """
  A fleet's Worldline, at `/worldline` under the fleet's address, drawn inside
  the fleet's page under its bar (`RegentsWeb.Keyfleet.FleetLive`): everything the
  reader may read of the fleet along one line, from its oldest event on the
  left to now on the right (`RegentsWeb.Keyfleet.WorldlinePage`).

  The picture is drawn in the browser (`assets/js/hooks/worldline.ts`), in
  space: the line runs through time to the sun at now, the workspace, code
  and notebooks are planets orbiting it for ever, each named beside it and
  linked to its place in the workspace (`WorkspacePage.place_path/3`), each
  event of theirs a bead on its planet's path, each room a dithered line of
  a pixel for each post, and everything fleet-wide a point on the line
  itself. While it shows now, the picture flies: the planets circle the line
  far faster than real time, each event turning with its planet's path at
  its own time, slowing while the reader is on one of its events or planets.
  The page sends it the newest events once it is live, older ones as the
  reader moves back to them, and new ones a moment after they happen.
  `?show=list` shows the same events as links, newest first, with "Older"
  for the page before.
  Every event links to the page it happened on.

  `?by=` keeps one Key's events or one wallet's (`WorldlinePage.by/1`), in
  the picture and the list alike; the filter field above them sets it.
  """

  use RegentsWeb, :html

  import Regents.Keyfleet.Fleets.Rules, only: [grouped: 1]

  import Phoenix.LiveView,
    only: [connected?: 1, push_event: 3, push_patch: 2, stream: 3, stream: 4, stream_insert: 4]

  alias Regents.Keyfleet.Fleets

  alias RegentsWeb.Keyfleet.{
    BoxLimit,
    PageRead,
    PollsLive,
    ShellLive,
    WorkspacePage,
    WorldlinePage
  }

  # How many of each source's events a read takes: the picture's, the
  # list's, and a read of what was just heard.
  @picture_read 100
  @list_read 20
  @heard_read 20

  # The three planets, each with its place in the fleet's workspace: the
  # project's goals and tasks, its code, and its docs, where the notebooks
  # are. The legend names them for every reader, as they hold no events of
  # their own, each a link to its place, and then each other source the
  # reader reads.
  @planets [
    {"workspace", "Workspace", :project},
    {"code", "Code", :code},
    {"notebooks", "Notebooks", :docs}
  ]
  @legend [
    posts: {"chat", "Chat"},
    opened: {"proposals", "Proposals"},
    votes: {"votes", "Votes"},
    polls: {"polls", "Polls"},
    keys: {"keys", "Keys"},
    shards: {"shards", "Shards"},
    present: {"present", "Present"},
    treasury: {"treasury", "Treasury"},
    projects: {"projects", "Projects"}
  ]

  # What each notice the page hears asks to be read again.
  @heard %{
    polls: [:polls, :stopped],
    proposals: [:opened, :closed, :votes, :executed, :cancelled, :treasury],
    keys: [:keys, :shards]
  }

  @doc """
  The fleet's Worldline, as the picture or as the list, with only the events
  of `by` (`WorldlinePage.by/1`), or everyone's when nil.
  """
  def worldline_path(fleet_id, show \\ :picture, by \\ nil) do
    query = for {name, value} <- [show: shown(show), by: words(by)], value, do: {name, value}
    path = "#{Fleets.path(fleet_id)}/worldline"
    if query == [], do: path, else: path <> "?" <> URI.encode_query(query)
  end

  defp shown(:picture), do: nil
  defp shown(:list), do: "list"

  # A filter as the address and the field write it.
  defp words(nil), do: nil
  defp words({:key, key}), do: Integer.to_string(key)
  defp words({:wallet, wallet}), do: wallet

  @doc "The id of an event's line in the list."
  def dom_id(%{id: id}), do: "worldline-" <> String.replace(id, ":", "-")

  @doc """
  The Worldline named in the address, read newest first as the reader. The
  picture is read once the page is live, as only the browser draws it. A
  filter in the address that names no Key or wallet reads nothing and says
  so beside the field. Leaving the Worldline clears it.
  """
  def read(socket, :worldline, %{"fleet_id" => fleet_id} = params) do
    show = if params["show"] == "list", do: :list, else: :picture
    read_as = ShellLive.reads_as(socket, fleet_id)
    {by, wrong?} = filter(params["by"])

    worldline = %{
      fleet_id: fleet_id,
      show: show,
      state: :read,
      cursor: nil,
      empty?: false,
      heard: [],
      by: by,
      asked: params["by"],
      typed: if(wrong?, do: unread(params["by"]), else: typed(by)),
      wrong?: wrong?,
      legend: legend(fleet_id, read_as)
    }

    socket = stream(socket, :worldline, [], reset: true)

    cond do
      show == :picture and not connected?(socket) -> assign(socket, :worldline, worldline)
      wrong? -> socket |> assign(:worldline, worldline) |> show_newest(show, [], nil)
      true -> read_newest(socket, worldline, read_as)
    end
  end

  def read(%{assigns: %{worldline: nil}} = socket, _route_id, _params), do: socket

  def read(socket, _route_id, _params),
    do: socket |> assign(:worldline, nil) |> stream(:worldline, [], reset: true)

  # The filter the address names, and whether its words name nothing.
  defp filter(words) do
    case WorldlinePage.by(words || "") do
      {:ok, by} -> {by, false}
      :error -> {nil, true}
    end
  end

  # The planets with their links, then what the reader may read of the rest.
  defp legend(fleet_id, read_as) do
    sources = WorldlinePage.sources(fleet_id, read_as)

    planets(fleet_id) ++
      for {source, {trail, name}} <- @legend, source in sources, do: {trail, name, nil}
  end

  # Each planet's trail, name and the path of its place in the workspace.
  defp planets(fleet_id) do
    for {trail, name, place} <- @planets,
        do: {trail, name, WorkspacePage.place_path(fleet_id, place)}
  end

  # A filter as the field shows it.
  defp typed(nil), do: ""
  defp typed({:key, key}), do: "Key #{key}"
  defp typed({:wallet, wallet}), do: wallet

  # Words that name nothing, from the address or the field, as far as the
  # field keeps them.
  defp unread(words), do: BoxLimit.kept(words, WorldlinePage.longest_filter())

  defp read_newest(socket, %{fleet_id: fleet_id, show: show} = worldline, read_as) do
    case PageRead.run("worldline", fn ->
           WorldlinePage.page(fleet_id, nil, [limit: limit(show), by: worldline.by] ++ read_as)
         end) do
      {:ok, %{events: events, cursor: cursor}} ->
        socket
        |> assign(:worldline, %{worldline | cursor: cursor, empty?: events == []})
        |> show_newest(show, events, cursor)

      {:error, _failure} ->
        assign(socket, :worldline, %{worldline | state: :unreadable})
    end
  end

  defp limit(:picture), do: @picture_read
  defp limit(:list), do: @list_read

  # The picture takes the time it was read by, so it draws now where the
  # events have it, whatever the reader's own clock says.
  defp show_newest(socket, :picture, events, cursor) do
    push_event(socket, "worldline:page", %{
      events: Enum.map(events, &payload/1),
      older: cursor != nil,
      now: System.system_time(:millisecond)
    })
  end

  defp show_newest(socket, :list, events, _cursor),
    do: stream(socket, :worldline, Enum.reverse(events), reset: true)

  @doc """
  The page before the oldest on show: the picture asks for it as the reader
  pans back to it and takes it as the reply; the list's "Older" adds it under
  the events on show.
  """
  def handle_event(
        "worldline_older",
        _params,
        %{assigns: %{worldline: %{cursor: cursor} = worldline}} = socket
      )
      when cursor != nil do
    %{events: events, cursor: next} =
      WorldlinePage.page(
        worldline.fleet_id,
        cursor,
        [limit: limit(worldline.show), by: worldline.by] ++
          ShellLive.reads_as(socket, worldline.fleet_id)
      )

    socket = assign(socket, :worldline, %{worldline | cursor: next})

    case worldline.show do
      :picture -> {:reply, %{events: Enum.map(events, &payload/1), older: next != nil}, socket}
      :list -> {:noreply, stream(socket, :worldline, Enum.reverse(events))}
    end
  end

  def handle_event("worldline_older", _params, socket), do: {:noreply, socket}

  # The filter's words: a Key or a wallet goes into the address, which reads
  # the Worldline again; anything else is answered beside the field.
  def handle_event(
        "worldline_filter",
        %{"by" => words},
        %{assigns: %{worldline: %{} = worldline}} = socket
      ) do
    case WorldlinePage.by(words) do
      {:ok, by} ->
        {:noreply, push_patch(socket, to: worldline_path(worldline.fleet_id, worldline.show, by))}

      :error ->
        {:noreply, assign(socket, :worldline, %{worldline | typed: unread(words), wrong?: true})}
    end
  end

  def handle_event("worldline_filter", _params, socket), do: {:noreply, socket}

  @doc """
  Something happened in one of the Worldline's sources: `:posts`,
  `:changes`, `:pushes`, `:polls`, `:proposals`, `:keys` or `:present`. A
  burst is read once, a moment later, as the fleet's hall reads its feed.
  """
  def heard(%{assigns: %{worldline: %{state: :read, heard: heard} = worldline}} = socket, source) do
    if heard == [] do
      Process.send_after(
        self(),
        :refresh_worldline,
        Application.fetch_env!(:regents, :keyfleet_fleet_feed_wait_ms)
      )
    end

    sources = Map.get(@heard, source, [source])
    assign(socket, :worldline, %{worldline | heard: Enum.uniq(heard ++ sources)})
  end

  def heard(socket, _source), do: socket

  @doc "As `heard/2`, for a notice that names its fleet: only the Worldline of that fleet hears it."
  def heard(%{assigns: %{worldline: %{fleet_id: fleet_id}}} = socket, fleet_id, source),
    do: heard(socket, source)

  def heard(socket, _fleet_id, _source), do: socket

  @doc "The newest events of the sources heard, added to what is on show."
  def handle_info(
        :refresh_worldline,
        %{assigns: %{worldline: %{heard: [_ | _] = heard} = worldline}} = socket
      ) do
    %{events: events} =
      WorldlinePage.page(
        worldline.fleet_id,
        nil,
        [limit: @heard_read, only: heard, by: worldline.by] ++
          ShellLive.reads_as(socket, worldline.fleet_id)
      )

    socket =
      assign(socket, :worldline, %{
        worldline
        | heard: [],
          empty?: worldline.empty? and events == []
      })

    case worldline.show do
      :picture ->
        {:noreply, push_event(socket, "worldline:heard", %{events: Enum.map(events, &payload/1)})}

      :list ->
        {:noreply, Enum.reduce(events, socket, &stream_insert(&2, :worldline, &1, at: 0))}
    end
  end

  def handle_info(:refresh_worldline, socket), do: {:noreply, socket}

  @doc """
  The reader's class in the fleet changed: the Worldline is read again as it
  now reads, with the same filter, and hears the polls only if it now reads
  them.
  """
  def class_changed(
        %{assigns: %{worldline: %{fleet_id: fleet_id, show: show, asked: asked}}} = socket,
        fleet_id
      ) do
    params = %{"fleet_id" => fleet_id, "show" => Atom.to_string(show), "by" => asked}
    socket |> PollsLive.read_polls(:worldline, params) |> read(:worldline, params)
  end

  def class_changed(socket, _fleet_id), do: socket

  # An event as the picture takes it: its time in milliseconds and who did it
  # in words.
  defp payload(event) do
    %{
      id: event.id,
      at: DateTime.to_unix(event.at, :millisecond),
      trail: event.trail,
      kind: event.kind,
      place: event.place,
      who: event.key && "Key #{grouped(event.key)}",
      what: event.what,
      title: event.title,
      path: event.path,
      live: event.live?
    }
  end

  attr :worldline, :map, required: true, doc: "the Worldline as `read/3` reads it"
  attr :events, :any, required: true, doc: "the list's events, as a stream"

  def page(assigns) do
    ~H"""
    <article id="worldline-page" class="worldline-page">
      <section class="worldline-panel" aria-labelledby="worldline-title">
        <header class="worldline-head">
          <h2 id="worldline-title">
            Worldline
            <Regent.Primitives.tip id="worldline-title-tip" label="About Worldline">
              Live 3D timeline of fleet events. Switch to List to browse as text.
            </Regent.Primitives.tip>
          </h2>
          <nav id="worldline-show" class="fleet-keys-switch" aria-label="Show the Worldline as">
            <.link
              id="worldline-show-picture"
              patch={worldline_path(@worldline.fleet_id, :picture, @worldline.by)}
              aria-current={if @worldline.show == :picture, do: "page"}
            >
              Picture
            </.link>
            <.link
              id="worldline-show-list"
              patch={worldline_path(@worldline.fleet_id, :list, @worldline.by)}
              aria-current={if @worldline.show == :list, do: "page"}
            >
              List
            </.link>
          </nav>
        </header>

        <ul id="worldline-legend" class="worldline-legend" aria-label="Legend">
          <li :for={{trail, name, path} <- @worldline.legend} data-trail={trail}>
            <.link :if={path} patch={path}>{name}</.link>
            <span :if={path == nil}>{name}</span>
          </li>
        </ul>

        <form
          :if={@worldline.state == :read}
          id="worldline-filter"
          class="worldline-filter"
          phx-submit="worldline_filter"
        >
          <Regent.Primitives.field
            :let={field}
            id="worldline-filter-by"
            label="Filter"
            errors={if @worldline.wrong?, do: ["Enter a Key number or a 0x address."], else: []}
          >
            <input
              id={field.id}
              name="by"
              type="search"
              maxlength={BoxLimit.maxlength(WorldlinePage.longest_filter())}
              value={@worldline.typed}
              placeholder="Key 19 or 0x…"
              autocomplete="off"
              autocapitalize="off"
              spellcheck="false"
              enterkeyhint="search"
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by != "" && field.described_by}
            />
          </Regent.Primitives.field>
          <Regent.Primitives.button
            id="worldline-filter-apply"
            type="submit"
            variant="secondary"
            arrow={false}
          >
            Apply
          </Regent.Primitives.button>
          <.link
            :if={@worldline.asked not in [nil, ""] or @worldline.wrong?}
            id="worldline-filter-clear"
            class="worldline-filter__clear"
            patch={worldline_path(@worldline.fleet_id, @worldline.show)}
          >
            Clear
          </.link>
        </form>

        <Regent.Primitives.empty_state
          :if={@worldline.state == :unreadable}
          id="worldline-unreadable"
          class="kf-empty"
          title="The Worldline couldn’t be loaded. Refresh the page to try again."
        />

        <.picture
          :if={@worldline.show == :picture and @worldline.state == :read}
          worldline={@worldline}
        />

        <Regent.Primitives.empty_state
          :if={@worldline.state == :read and @worldline.empty?}
          id="worldline-empty"
          class="kf-empty"
          title={
            if @worldline.by,
              do: "Nothing matches this filter yet.",
              else: "Nothing has happened in this fleet yet."
          }
        />

        <ol
          :if={@worldline.show == :list and @worldline.state == :read}
          id="worldline-events"
          class="worldline-events"
          phx-update="stream"
        >
          <li :for={{dom_id, event} <- @events} id={dom_id} data-trail={trail(event)}>
            <.link {to(event)} class="worldline-event">
              <span class="worldline-event__head">
                <span class="worldline-event__what">{event.what}</span>
                <span :if={event.key} class="worldline-event__who">Key {grouped(event.key)}</span>
                <RegentsWeb.Keyfleet.Time.local
                  id={dom_id <> "-at"}
                  at={event.at}
                  as={:moment}
                  class="worldline-event__at"
                />
              </span>
              <span class="worldline-event__title">{event.title}</span>
            </.link>
          </li>
        </ol>

        <Regent.Primitives.button
          :if={@worldline.show == :list and @worldline.cursor != nil}
          id="worldline-older"
          type="button"
          variant="secondary"
          arrow={false}
          phx-click="worldline_older"
        >
          Older
        </Regent.Primitives.button>
      </section>
    </article>
    """
  end

  attr :worldline, :map, required: true

  # The picture the browser draws, and what stands until it does: the line
  # and the sun at now. Once it is drawn, each planet at now carries its name,
  # the name and the planet one link to its place in the workspace, and the
  # sun carries Now. One link follows the event pointed at, so it opens as any
  # link does, in a new tab too; a word names what just arrived at the sun,
  # and Now goes back to it. The zoom and Reset stand in a corner.
  defp picture(assigns) do
    ~H"""
    <div
      id="worldline-stage"
      class="worldline-stage"
      phx-hook="Worldline"
      phx-update="ignore"
      phx-mounted={
        JS.ignore_attributes(["data-worldline-ready", "data-worldline-still", "data-dragging"])
      }
      tabindex="0"
      role="group"
      aria-labelledby="worldline-title"
      aria-describedby="worldline-help"
    >
      <canvas class="worldline-stage__canvas" data-worldline-canvas aria-hidden="true"></canvas>
      <span class="worldline-stage__line" aria-hidden="true"></span>
      <span class="worldline-stage__head" aria-hidden="true"></span>
      <p class="worldline-stage__still">
        Your browser can’t draw this picture.
        <.link patch={worldline_path(@worldline.fleet_id, :list)}>List</.link>
        has every event.
      </p>
      <span class="worldline-news" data-worldline-news aria-hidden="true"></span>
      <a class="worldline-focus" data-worldline-focus draggable="false" hidden>
        <span class="worldline-focus__card" data-focus-card>
          <span class="worldline-focus__what" data-focus-what></span>
          <span class="worldline-focus__title" data-focus-title></span>
          <span class="worldline-focus__meta" data-focus-meta></span>
        </span>
      </a>
      <div class="worldline-tips" data-worldline-tips>
        <.link
          :for={{trail, name, path} <- planets(@worldline.fleet_id)}
          class="worldline-tip"
          data-trail={trail}
          data-worldline-tip={trail}
          patch={path}
          draggable="false"
        >
          <span class="worldline-tip__name" data-tip-name>{name}</span>
        </.link>
        <span class="worldline-tip worldline-tip--now" data-worldline-tip="now" aria-hidden="true">
          <span class="worldline-tip__name" data-tip-name>Now</span>
        </span>
      </div>
      <div class="worldline-view" role="group" aria-label="View" data-worldline-view>
        <button type="button" aria-label="Zoom out" data-worldline-zoom="out">−</button>
        <output aria-label="Zoom" data-worldline-zoom-level>100%</output>
        <button type="button" aria-label="Zoom in" data-worldline-zoom="in">+</button>
        <button type="button" data-worldline-reset>Reset</button>
      </div>
      <Regent.Primitives.button
        variant="secondary"
        arrow={false}
        class="worldline-now"
        data-worldline-now
        hidden
      >
        Now
      </Regent.Primitives.button>
    </div>
    <p id="worldline-help" class="worldline-help">
      <span class="worldline-help__mouse">
        Drag to rotate · Shift + drag or scroll to move in time · Ctrl + scroll to zoom.
      </span>
      <span class="worldline-help__touch">
        Swipe to move in time · Pinch to zoom · Twist with two fingers to rotate.
      </span>
      <span class="visually-hidden">
        Arrow keys move through time, Alt and the arrow keys turn it, plus and minus zoom, End goes back to now, and Enter opens the event shown.
      </span>
    </p>
    <Regent.Primitives.disclosure
      id="worldline-orbits"
      class="worldline-orbits"
      summary="Controls and orbits"
    >
      <p>
        One orbit equals a day for Workspace, three days for Code, and a week for Notebooks.
      </p>
      <p class="worldline-help__flight">
        At Now, planets spin faster and slow on hover or tap; scrubbing through time pauses them, and Now resumes playback.
      </p>
      <p>
        Keyboard: Arrow keys move in time, Alt + arrows rotate, +/- zoom, End returns to Now, Enter opens the selected event.
      </p>
    </Regent.Primitives.disclosure>
    """
  end

  defp to(%{live?: true, path: path}), do: %{patch: path}
  defp to(%{live?: false, path: path}), do: %{href: path}

  # The colour an event's mark takes, as its legend shows it.
  defp trail(%{trail: "room:" <> _slug}), do: "chat"
  defp trail(%{kind: kind}) when kind in [:poll, :poll_stopped], do: "polls"

  defp trail(%{kind: kind})
       when kind in [:proposal_opened, :proposal_closed, :executed, :cancelled],
       do: "proposals"

  defp trail(%{kind: :vote}), do: "votes"
  defp trail(%{kind: kind}) when kind in [:sold, :given, :transfer], do: "keys"
  defp trail(%{kind: kind}) when kind in [:shard_lent, :shard_ended], do: "shards"
  defp trail(%{kind: :present}), do: "present"
  defp trail(%{kind: kind}) when kind in [:daily_split, :claimed], do: "treasury"
  defp trail(%{kind: :project}), do: "projects"
  defp trail(%{trail: trail}), do: trail
end
