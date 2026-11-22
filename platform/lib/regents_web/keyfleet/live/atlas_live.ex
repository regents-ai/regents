defmodule RegentsWeb.Keyfleet.AtlasLive do
  @moduledoc """
  A fleet's Atlas, at `/atlas` under the fleet's address, drawn inside the
  fleet's page under its bar (`RegentsWeb.Keyfleet.FleetLive`): all of the fleet's
  work over time, its workspace's items and its notebooks together, from the
  whole swarm down to one thing, read from `RegentsWeb.Keyfleet.AtlasPage`. Only the
  fleet's members read it, as they read its workspace; anyone else is told so.

  The address holds everything the page shows: the Blocks
  (`RegentsWeb.Keyfleet.AtlasLive.Blocks` and `assets/js/atlas/blocks/`) unless
  `?show=list` names the List, the same work as text and links; `?window=` the
  day, week, month or year shown (a year unless named), `?at=` a day it holds
  (today unless named), and `?kind=` `graph` or `notebooks` for one of them.

  The Blocks are drawn in the browser, which asks the page for the counts and
  things on screen as the reader opens them (`Blocks.handle_event/3`), beside
  the most active things of the window shown. The List reads the
  window's totals, each project's share, the most active things and the
  latest, a page at a time. New work reaches both a moment after it is
  counted (`heard/2`), at most once a moment however much arrives.
  """

  use RegentsWeb, :html

  import Phoenix.LiveView,
    only: [connected?: 1, push_event: 3, stream: 3, stream: 4]

  alias RegentsWeb.Keyfleet.AtlasLive.Blocks
  alias RegentsWeb.Keyfleet.{AtlasPage, PageRead, ShellLive}

  @kinds %{"graph" => :graph, "notebooks" => :notebook}
  @list_read 20
  @most_read 10
  @active_read 8

  @doc """
  The Atlas with `opts` (`:show`, `:window`, `:at` a `Date`, and `:kind`),
  each left out of the address when it is the one shown unless named.
  """
  def atlas_path(fleet_id, opts \\ []) do
    query =
      for {name, value} <- [
            show: opts[:show] == :list && "list",
            window: opts[:window] not in [nil, :year] && opts[:window],
            kind: kind_word(opts[:kind]),
            at: opts[:at] && Date.to_iso8601(opts[:at])
          ],
          value,
          do: {name, value}

    path = "#{Regents.Keyfleet.Fleets.path(fleet_id)}/atlas"
    if query == [], do: path, else: path <> "?" <> URI.encode_query(query)
  end

  defp kind_word(:graph), do: "graph"
  defp kind_word(:notebook), do: "notebooks"
  defp kind_word(nil), do: nil

  @doc "The id of a thing's line in the List."
  def dom_id(%{id: id}), do: "atlas-thing-" <> Base.url_encode64(id, padding: false)

  @doc """
  The Atlas named in the address, read as the reader. The picture's rows and
  the window's most active things are read once the page is live, as only
  the browser draws it. Leaving the Atlas clears it.
  """
  def read(socket, :atlas, %{"fleet_id" => fleet_id} = params) do
    window = window(params["window"])
    at = at(params["at"])

    atlas = %{
      fleet_id: fleet_id,
      show: if(params["show"] == "list", do: :list, else: :picture),
      window: window,
      at: at,
      source: @kinds[params["kind"]],
      state: :read,
      rows: [],
      active: nil,
      totals: nil,
      projects: [],
      most: [],
      after: nil,
      paged?: false,
      # A read of new work already on its way still comes, after a move.
      heard?: match?(%{fleet_id: ^fleet_id, heard?: true}, socket.assigns.atlas)
    }

    socket = stream(socket, :atlas_things, [], reset: true)

    cond do
      not ShellLive.member?(socket, fleet_id) ->
        assign(socket, :atlas, %{atlas | state: :members_only})

      atlas.show == :picture and not connected?(socket) ->
        assign(socket, :atlas, atlas)

      true ->
        read_shown(socket, atlas)
    end
  end

  def read(%{assigns: %{atlas: nil}} = socket, _route_id, _params), do: socket

  def read(socket, _route_id, _params),
    do: socket |> assign(:atlas, nil) |> stream(:atlas_things, [], reset: true)

  defp window(word) when word in ~w(day week month), do: String.to_existing_atom(word)
  defp window(_word), do: :year

  # The start of the day the address names, or of now's.
  defp at(word) do
    case Date.from_iso8601(word || "") do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      {:error, _} -> DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end

  defp read_shown(socket, atlas) do
    read_as = ShellLive.reads_as(socket, atlas.fleet_id)

    case PageRead.run("atlas", fn -> read_parts(atlas, read_as) end) do
      {:ok, {atlas, things}} ->
        socket
        |> assign(:atlas, atlas)
        |> stream(:atlas_things, things, reset: true)

      {:error, _failure} ->
        assign(socket, :atlas, %{atlas | state: :unreadable})
    end
  end

  defp read_parts(%{show: :picture} = atlas, read_as) do
    rows = AtlasPage.rows(atlas.fleet_id, atlas.source, read_as)
    {%{atlas | rows: rows, active: active(atlas, atlas.window, atlas.at, read_as)}, []}
  end

  defp read_parts(%{show: :list} = atlas, read_as) do
    %{fleet_id: fleet_id, window: window, at: at, source: source} = atlas
    opts = [source: source] ++ read_as
    most = AtlasPage.most_active(fleet_id, window, at, [limit: @most_read] ++ opts)
    latest = AtlasPage.newest(fleet_id, window, at, [limit: @list_read] ++ opts)

    {%{
       atlas
       | totals: AtlasPage.totals(fleet_id, window, at, source, read_as),
         projects: AtlasPage.projects(fleet_id, window, at, source, read_as),
         most: most.things,
         after: latest.after
     }, latest.things}
  end

  # The most active things of the window of `span` holding `at`, for the
  # strip beside the picture.
  defp active(atlas, span, at, read_as) do
    %{things: things} =
      AtlasPage.most_active(
        atlas.fleet_id,
        span,
        at,
        [limit: @active_read, source: atlas.source] ++ read_as
      )

    {start, _end} = AtlasPage.window(span, at)
    %{span: span, start: start, things: things}
  end

  @doc """
  What the page is asked as the reader moves: the List's `atlas_older` adds
  the next page of the latest things under those on show, and the Blocks'
  `atlas_blocks_` events are answered by `Blocks.handle_event/3`.
  """
  def handle_event(
        "atlas_older",
        _params,
        %{assigns: %{atlas: %{state: :read, show: :list, after: cursor} = atlas}} = socket
      )
      when cursor != nil do
    %{things: things, after: next} =
      AtlasPage.newest(
        atlas.fleet_id,
        atlas.window,
        atlas.at,
        [limit: @list_read, source: atlas.source, after: cursor] ++
          ShellLive.reads_as(socket, atlas.fleet_id)
      )

    {:noreply,
     socket
     |> assign(:atlas, %{atlas | after: next, paged?: true})
     |> stream(:atlas_things, things)}
  end

  def handle_event("atlas_blocks_" <> _ = event, params, socket),
    do: Blocks.handle_event(event, params, socket)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @doc """
  The fleet's Atlas has counted more: it is read again a moment later, once
  for however much arrives meanwhile.
  """
  def heard(%{assigns: %{atlas: %{fleet_id: fleet_id, state: :read} = atlas}} = socket, fleet_id) do
    if atlas.heard? do
      socket
    else
      Process.send_after(
        self(),
        :refresh_atlas,
        Application.fetch_env!(:regents, :keyfleet_fleet_feed_wait_ms)
      )

      assign(socket, :atlas, %{atlas | heard?: true})
    end
  end

  def heard(socket, _fleet_id), do: socket

  @doc """
  What was heard, read: the picture's rows and strip again, and the picture
  told to read what it shows again; the List's totals and most active, and
  its latest when the reader has not read on past the first page.
  """
  def handle_info(:refresh_atlas, %{assigns: %{atlas: %{heard?: true} = atlas}} = socket) do
    atlas = %{atlas | heard?: false}
    read_as = ShellLive.reads_as(socket, atlas.fleet_id)

    case atlas.show do
      :picture ->
        %{span: span, start: start} = atlas.active

        {:noreply,
         socket
         |> assign(:atlas, %{
           atlas
           | rows: AtlasPage.rows(atlas.fleet_id, atlas.source, read_as),
             active: active(atlas, span, start, read_as)
         })
         |> push_event("atlas:changed", %{})}

      :list when atlas.paged? ->
        {fresh, _things} = read_parts(atlas, read_as)
        {:noreply, assign(socket, :atlas, %{fresh | after: atlas.after, paged?: true})}

      :list ->
        {fresh, things} = read_parts(atlas, read_as)

        {:noreply, socket |> assign(:atlas, fresh) |> stream(:atlas_things, things, reset: true)}
    end
  end

  def handle_info(:refresh_atlas, socket), do: {:noreply, socket}

  @doc "The reader's class in the fleet changed: the Atlas is read again as it now reads."
  def class_changed(%{assigns: %{atlas: %{fleet_id: fleet_id} = atlas}} = socket, fleet_id) do
    params =
      %{
        "fleet_id" => fleet_id,
        "window" => Atom.to_string(atlas.window),
        "at" => atlas.at |> DateTime.to_date() |> Date.to_iso8601(),
        "kind" => kind_word(atlas.source)
      }
      |> Map.merge(if atlas.show == :list, do: %{"show" => "list"}, else: %{})

    read(socket, :atlas, params)
  end

  def class_changed(socket, _fleet_id), do: socket

  @doc "A window as a reader names it: a day, a week from its Monday, a month, a year, or an hour."
  def window_label(:hour, start), do: Calendar.strftime(start, "%-d %b %Y, %H:00 UTC")
  def window_label(:day, start), do: Calendar.strftime(start, "%-d %b %Y")
  def window_label(:week, start), do: Calendar.strftime(start, "Week of %-d %b %Y")
  def window_label(:month, start), do: Calendar.strftime(start, "%B %Y")
  def window_label(:year, start), do: Calendar.strftime(start, "%Y")

  attr :atlas, :map, required: true, doc: "the Atlas as `read/3` reads it"
  attr :things, :any, required: true, doc: "the List's latest things, as a stream"
  attr :signed_out?, :boolean, required: true

  def page(%{atlas: %{state: :members_only}} = assigns) do
    ~H"""
    <article id="atlas-page" class="atlas-page">
      <section class="atlas-panel" aria-labelledby="atlas-title">
        <header class="atlas-head">
          <h2 id="atlas-title">Atlas</h2>
        </header>
        <Regent.Primitives.empty_state
          id="atlas-members-only"
          class="kf-empty"
          title="Only this fleet’s Key holders and their agents see its work over time."
        >
          <:action>
            <.link patch={RegentsWeb.Keyfleet.KeyLinks.members_path(@atlas.fleet_id)}>
              See this fleet’s Keys
            </.link>
            <Regent.Primitives.button
              :if={@signed_out?}
              id="atlas-sign-in"
              type="button"
              variant="secondary"
              arrow={false}
              data-account-target="sign-in"
            >
              Sign in
            </Regent.Primitives.button>
          </:action>
        </Regent.Primitives.empty_state>
      </section>
    </article>
    """
  end

  def page(assigns) do
    ~H"""
    <article id="atlas-page" class="atlas-page">
      <section class="atlas-panel" aria-labelledby="atlas-title">
        <header class="atlas-head">
          <h2 id="atlas-title">Atlas</h2>
          <nav id="atlas-show" class="fleet-keys-switch" aria-label="Show the Atlas as">
            <.link
              id="atlas-show-blocks"
              patch={moved(@atlas, show: :picture)}
              aria-current={if @atlas.show == :picture, do: "page"}
            >
              Blocks
            </.link>
            <.link
              id="atlas-show-list"
              patch={moved(@atlas, show: :list)}
              aria-current={if @atlas.show == :list, do: "page"}
            >
              List
            </.link>
          </nav>
        </header>

        <div class="atlas-controls">
          <nav id="atlas-window" class="fleet-keys-switch" aria-label="Window">
            <.link
              :for={window <- AtlasPage.windows()}
              id={"atlas-window-#{window}"}
              patch={moved(@atlas, window: window)}
              aria-current={if @atlas.window == window, do: "page"}
            >
              {window |> Atom.to_string() |> String.capitalize()}
            </.link>
          </nav>
          <nav id="atlas-kind" class="fleet-keys-switch" aria-label="Kind">
            <.link
              :for={{kind, label} <- [{nil, "All"}, {:graph, "Graph"}, {:notebook, "Notebooks"}]}
              id={"atlas-kind-#{kind_word(kind) || "all"}"}
              patch={moved(@atlas, kind: kind)}
              aria-current={if @atlas.source == kind, do: "page"}
            >
              {label}
            </.link>
          </nav>
        </div>

        <Regent.Primitives.empty_state
          :if={@atlas.state == :unreadable}
          id="atlas-unreadable"
          class="kf-empty"
          title="The Atlas couldn’t be loaded. Refresh the page to try again."
        />

        <Blocks.picture
          :if={@atlas.state == :read and @atlas.show == :picture}
          atlas={@atlas}
        />

        <.list :if={@atlas.state == :read and @atlas.show == :list} atlas={@atlas} things={@things} />
      </section>
    </article>
    """
  end

  attr :atlas, :map, required: true
  attr :things, :any, required: true

  # The window as text: its totals, each project's share, its most active
  # things and its latest, each a link to its own page.
  defp list(assigns) do
    {start, _end} = AtlasPage.window(assigns.atlas.window, assigns.atlas.at)
    assigns = assign(assigns, :start, start)

    ~H"""
    <div id="atlas-list" class="atlas-list">
      <nav class="atlas-list__window" aria-label="Move through time">
        <.link id="atlas-earlier" patch={moved(@atlas, at: shifted(@atlas, -1))}>Earlier</.link>
        <h3 id="atlas-window-label">{window_label(@atlas.window, @start)}</h3>
        <.link id="atlas-later" patch={moved(@atlas, at: shifted(@atlas, 1))}>Later</.link>
      </nav>

      <dl id="atlas-totals" class="atlas-totals">
        <div>
          <dt>Changes</dt>
          <dd>{grouped(@atlas.totals.changes)}</dd>
        </div>
        <div>
          <dt>Things</dt>
          <dd>{grouped(@atlas.totals.things)}</dd>
        </div>
        <div>
          <dt>Keys</dt>
          <dd>{grouped(@atlas.totals.actors)}</dd>
        </div>
      </dl>

      <Regent.Primitives.empty_state
        :if={@atlas.totals.changes == 0}
        id="atlas-empty"
        class="kf-empty"
        title="Nothing changed in this window."
      />

      <section :if={@atlas.projects != []} aria-labelledby="atlas-projects-title">
        <h3 id="atlas-projects-title">Projects</h3>
        <table id="atlas-projects" class="atlas-table">
          <thead>
            <tr>
              <th scope="col">Project</th>
              <th scope="col">Changes</th>
              <th scope="col">Things</th>
              <th scope="col">Keys</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={project <- @atlas.projects} id={"atlas-project-#{project.project}"}>
              <th scope="row">{project.title}</th>
              <td>{grouped(project.changes)}</td>
              <td>{grouped(project.things)}</td>
              <td>{grouped(project.actors)}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section :if={@atlas.most != []} aria-labelledby="atlas-most-title">
        <h3 id="atlas-most-title">Active</h3>
        <ol id="atlas-most" class="atlas-things">
          <li :for={thing <- @atlas.most} id={"atlas-most-" <> dom_id(thing)}>
            <.thing thing={thing} id={"atlas-most-" <> dom_id(thing)} />
          </li>
        </ol>
      </section>

      <section :if={@atlas.totals.changes > 0} aria-labelledby="atlas-latest-title">
        <h3 id="atlas-latest-title">Latest</h3>
        <ol id="atlas-latest" class="atlas-things" phx-update="stream">
          <li :for={{dom_id, thing} <- @things} id={dom_id}>
            <.thing thing={thing} id={dom_id} />
          </li>
        </ol>
        <Regent.Primitives.button
          :if={@atlas.after != nil}
          id="atlas-older"
          type="button"
          variant="secondary"
          arrow={false}
          phx-click="atlas_older"
        >
          Older
        </Regent.Primitives.button>
      </section>
    </div>
    """
  end

  attr :thing, :map, required: true
  attr :id, :string, required: true

  defp thing(assigns) do
    ~H"""
    <.link {to(@thing)} class="atlas-thing">
      <span class="atlas-thing__head">
        <span class="atlas-pill" data-kind={@thing.kind}>{@thing.what}</span>
        <span :if={@thing.who} class="atlas-thing__who">{@thing.who}</span>
        <RegentsWeb.Keyfleet.Time.local
          id={@id <> "-at"}
          at={@thing.at}
          as={:moment}
          class="atlas-thing__at"
        />
      </span>
      <span class="atlas-thing__title">{@thing.title}</span>
      <span class="atlas-thing__count">
        {changes(@thing.changes)}<span :if={@thing.actors > 1}> · {@thing.actors} Keys</span>
      </span>
    </.link>
    """
  end

  @doc "A thing's link: a page of this site opened in place, or a notebook opened in full."
  def to(%{live?: true, path: path}), do: %{patch: path}
  def to(%{live?: false, path: path}), do: %{href: path}

  @doc "How many changes, in words."
  def changes(1), do: "1 change"
  def changes(count), do: "#{grouped(count)} changes"

  defp grouped(number), do: Regents.Keyfleet.Fleets.Rules.grouped(number)

  @doc "The address of the Atlas shown, with `changes` made to it, as `atlas_path/2` takes them."
  def moved(atlas, changes) do
    current = [
      show: atlas.show,
      window: atlas.window,
      kind: atlas.source,
      at: DateTime.to_date(atlas.at)
    ]

    atlas_path(atlas.fleet_id, Keyword.merge(current, changes))
  end

  # A day in the window `by` windows before or after the one shown.
  defp shifted(%{window: window, at: at}, by) do
    {start, finish} = AtlasPage.window(window, at)

    if by < 0,
      do: start |> DateTime.add(-1, :day) |> DateTime.to_date(),
      else: DateTime.to_date(finish)
  end
end
