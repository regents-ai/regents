defmodule RegentsWeb.Keyfleet.FleetNow do
  @moduledoc """
  What each fleet is doing right now, as a signed-out visitor reads it, read
  once for every open page and held in `Regents.SharedReading`. One runs on
  each machine.

  A fleet's reading holds whether it is coming soon and, once it is open:

    * `deployed?`, `current?` and `minted`: how far it has sold, as far as its
      Key history has been read (`Regents.Keyfleet.Chain.minted/2`, `fresh?/1`);
    * `feed`: the first page of its activity with no actor
      (`Regents.Keyfleet.Activity.page/3`), its items, the cursor for the page after
      them and `receivers`, the wallet each transfer among them went to
      (`Regents.Keyfleet.Activity.receivers/2`), for the hall's lines; and `faces`:
      who holds each Key that acted in them, the Key they write as and how
      many Keys they hold (`Regents.Keyfleet.Keys.faces/2`), for the city's discs;
    * `recent_work`: "Recent Work", each of its projects by title with the titles
      of its open goals (`RegentsWeb.Keyfleet.FleetPage.read_recent_work/1`);
    * `goal`: the title of its most recently changed open goal, and
      `headline`: the item it features (`Regents.Keyfleet.Activity.headline/2`), which
      the homepage shows;
    * `public`: the newest things its Keys made public, up to
      `@public_shown`, from the first page of its Public place as a
      signed-out visitor reads it (`RegentsWeb.Keyfleet.WorkspacePage.board/3`), each
      by its kind, its title in the Key's own words (an item's title, the
      first post's words, or a notebook page's or code's project title), cut
      to `@title_length` characters, its Key, and the address of its place on
      that page. One with no words to show, such as a notebook page in a
      project since deleted, is left out;
    * `page`: the newest notebook page a Key made public in a project the
      fleet still has, by that project's title, cut as a title is, its Key and
      the page's own address, which opens for anyone; nil while there is none;
    * `season`: the season under way as anyone reads it, with the one settled
      as it started (`RegentsWeb.Keyfleet.SeasonPanel.face/1`), for the hall's
      "Season" panel; nil while none is under way.

  Pages showing a fleet to a reader who isn't a member draw it from here: the
  homepage, the fleet hall and the harbour's sea; the header's "Buy Key"
  reads from it whether its fleet is open. A member's reading differs
  (rooms other than the Public room, the workspace's changes), so a member's
  page still reads under its own scope.

  This is a reread on notice, the second of the two shapes the `elixir-stack`
  skill lets keep a shared reading. It hears what an open page of a fleet hears
  as a non-member: the fleet's Keys, its public rooms, its notable workspace
  changes, its proposals and its seasons' turns. A burst of notices is
  answered by one read of each fleet named, a second after the first. Each minute
  `Regents.SharedReading.Heal` asks for every fleet again, which mends a lost
  notice and brings in a fleet's record when it opens; a coming-soon fleet
  costs that one read. Making something public, or taking it back, sends no
  notice, so the minute's heal brings it in. It holds nothing but which
  fleets are due a read, and it never writes the database.

  Before, every open page read its fleet itself, all of them after the same
  notice, so a crowd cost the database a read each in the same instant, and
  every page that reconnected after a deploy read again. Now a crowd costs
  what one visitor costs (`ash-frontend`, `references/public-figures.md`).

  The first read happens as it starts, with a bounded wait, so each fleet
  holds a reading or its degraded mark before the site serves a page, and a
  database that doesn't answer never holds up the start.
  """

  use GenServer

  alias Phoenix.Socket.Broadcast

  alias Regents.Keyfleet.{
    Activity,
    Chain,
    Fleets,
    Graph,
    Keys,
    Notebooks,
    Projects,
    Proposals,
    Rooms
  }

  alias Regents.Keyfleet.Seasons
  alias Regents.ProductActivity
  alias Regents.SharedReading

  alias RegentsWeb.Keyfleet.{
    ActivityLines,
    FleetPage,
    HarbourCrew,
    PageRead,
    SeasonPanel,
    WorkspacePage
  }

  # How many things made public the reading keeps: enough to run twice
  # across a wide screen, and each one on the Public place's first page.
  @public_shown 8

  # The most characters of a title the reading keeps.
  @title_length 64

  @doc "Where the reading of `fleet_id` is held."
  def key(fleet_id), do: {:keyfleet_fleet_now, fleet_id}

  @doc "The reading held for `fleet_id`, and whether its last read failed; nil while there is none."
  def fetch(fleet_id) do
    case SharedReading.fetch(key(fleet_id)) do
      {:ok, %{reading: %{} = reading, degraded?: degraded?}} -> {reading, degraded?}
      _not_read -> nil
    end
  end

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(nil) do
    SharedReading.register_producer(:keyfleet_fleet_now, self(), :sync)
    SharedReading.subscribe_heal(:keyfleet_fleet_now)
    ProductActivity.subscribe()

    # By topic, so a room's head, which names no fleet, is still a fleet's.
    topics =
      for fleet_id <- Fleets.catalog_ids(),
          topic <- [
            Keys.topic(fleet_id),
            Rooms.topic(fleet_id, :public),
            Graph.notable_topic(fleet_id),
            Proposals.topic(fleet_id),
            Seasons.topic(fleet_id)
          ],
          into: %{},
          do: {topic, fleet_id}

    Enum.each(Map.keys(topics), &Phoenix.PubSub.subscribe(Regents.PubSub, &1))
    {:ok, %{due: MapSet.new(), topics: topics, loaded?: false}}
  end

  @impl true
  def handle_call(:ensure_loaded, _from, %{loaded?: true} = state), do: {:reply, :ok, state}

  def handle_call(:ensure_loaded, _from, state) do
    ProductActivity.touch(:keyfleet)
    first_read(Fleets.catalog_ids())
    SharedReading.mark_loaded(:keyfleet_fleet_now, true)
    {:reply, :ok, %{state | due: MapSet.new(), loaded?: true}}
  end

  # Every fleet is read beside the start, all at once, so a slow database holds
  # the start for one wait, not one per fleet. The fleets table is read once for
  # the pass instead of once per fleet. Any not read in time is marked degraded;
  # its next notice or the heal reads it again.
  defp first_read(fleet_ids) do
    case recorded_fleets() do
      {:ok, recorded} ->
        fleet_ids
        |> Task.async_stream(&__MODULE__.read(&1, Map.get(recorded, &1)),
          max_concurrency: length(fleet_ids),
          timeout: Application.fetch_env!(:regents, :keyfleet_first_read_ms),
          on_timeout: :kill_task
        )
        |> Enum.zip(fleet_ids)
        |> Enum.each(fn
          {{:ok, _read}, _fleet_id} -> :ok
          {{:exit, :timeout}, fleet_id} -> SharedReading.degraded(key(fleet_id))
        end)

      :error ->
        Enum.each(fleet_ids, &SharedReading.degraded(key(&1)))
    end
  end

  @impl true
  def handle_info({:product_idle, :keyfleet}, %{loaded?: true} = state) do
    SharedReading.mark_loaded(:keyfleet_fleet_now, false)
    SharedReading.clear_kind(:keyfleet_fleet_now)
    {:noreply, %{state | due: MapSet.new(), loaded?: false}}
  end

  def handle_info({:product_idle, _product}, state), do: {:noreply, state}
  def handle_info({:product_active, _product}, state), do: {:noreply, state}

  def handle_info(%Broadcast{topic: topic}, %{loaded?: true} = state),
    do: {:noreply, due(state, state.topics[topic])}

  def handle_info(%Broadcast{}, state), do: {:noreply, state}

  def handle_info({:graph_notable, fleet_id}, %{loaded?: true} = state),
    do: {:noreply, due(state, fleet_id)}

  def handle_info({:graph_notable, _fleet_id}, state), do: {:noreply, state}

  def handle_info({:keys_changed, fleet_id, _token_ids}, %{loaded?: true} = state),
    do: {:noreply, due(state, fleet_id)}

  def handle_info({:keys_changed, _fleet_id, _token_ids}, state), do: {:noreply, state}

  # Presence isn't in the reading.
  def handle_info({:keys_present, _fleet_id, _token_ids}, state), do: {:noreply, state}

  def handle_info({:proposals_changed, fleet_id}, %{loaded?: true} = state),
    do: {:noreply, due(state, fleet_id)}

  def handle_info({:proposals_changed, _fleet_id}, state), do: {:noreply, state}

  # Balances aren't in the reading.
  def handle_info({:balances_changed, _fleet_id}, state), do: {:noreply, state}

  def handle_info({:shared_reading_heal, :keyfleet_fleet_now}, %{loaded?: true} = state) do
    if ProductActivity.active?(:keyfleet),
      do: {:noreply, Enum.reduce(Fleets.catalog_ids(), state, &due(&2, &1))},
      else: {:noreply, state}
  end

  def handle_info({:shared_reading_heal, :keyfleet_fleet_now}, state), do: {:noreply, state}

  def handle_info(:read, %{loaded?: true} = state) do
    if MapSet.size(state.due) > 0 and ProductActivity.active?(:keyfleet) do
      case recorded_fleets() do
        {:ok, recorded} ->
          Enum.each(state.due, &__MODULE__.read(&1, Map.get(recorded, &1)))

        :error ->
          Enum.each(state.due, &SharedReading.degraded(key(&1)))
      end
    end

    {:noreply, %{state | due: MapSet.new()}}
  end

  def handle_info(:read, state), do: {:noreply, %{state | due: MapSet.new()}}

  # The first fleet to fall due starts the one-second wait; the rest join it.
  defp due(state, fleet_id) do
    if MapSet.size(state.due) == 0, do: Process.send_after(self(), :read, 1_000)
    %{state | due: MapSet.put(state.due, fleet_id)}
  end

  defp recorded_fleets do
    case PageRead.run("fleet", fn -> Map.new(Fleets.list_fleets!(), &{&1.id, &1}) end) do
      {:ok, recorded} -> {:ok, recorded}
      {:error, _not_read} -> :error
    end
  end

  @doc "Reads `fleet_id` and puts its reading. What the producer runs on each pass."
  def read(fleet_id) do
    case PageRead.run("fleet", fn -> Fleets.get_fleet!(fleet_id) end) do
      {:ok, recorded} -> read(fleet_id, recorded)
      {:error, _not_read} -> SharedReading.degraded(key(fleet_id))
    end
  end

  @doc false
  def read(fleet_id, recorded) do
    case reading(fleet_id, recorded, DateTime.utc_now()) do
      {:ok, reading} -> SharedReading.put(key(fleet_id), reading)
      {:error, _not_read} -> SharedReading.degraded(key(fleet_id))
    end
  end

  # A failed database read is a read not taken, never a reason for this
  # process, and the site with it, to stop. It is logged and saved with the
  # site's errors as a page's own read is (`RegentsWeb.Keyfleet.PageRead`), so one that
  # keeps failing is seen at /admin/errors.
  defp reading(fleet_id, recorded, now) do
    PageRead.run("fleet", fn ->
      if Fleets.coming_soon?(fleet_id, recorded),
        do: %{coming_soon?: true},
        else: open(fleet_id, recorded, now)
    end)
  end

  defp open(fleet_id, recorded, now) do
    deployed? = recorded != nil and recorded.manager_address != nil
    %{items: items, cursor: cursor} = Activity.page(fleet_id, nil)
    board = WorkspacePage.board(fleet_id, %{"place" => "public"}, nil)

    %{
      coming_soon?: false,
      deployed?: deployed?,
      chain_id: if(deployed?, do: recorded.chain_id),
      current?: deployed? and Chain.fresh?(fleet_id),
      minted: if(deployed?, do: minted!(fleet_id), else: 0),
      feed: %{items: items, cursor: cursor, receivers: Activity.receivers(fleet_id, items)},
      faces: Keys.faces(fleet_id, HarbourCrew.keys(items)),
      recent_work: FleetPage.read_recent_work(fleet_id),
      goal: goal(fleet_id),
      headline: Activity.headline(fleet_id, now),
      public: board.public |> Enum.flat_map(&public(fleet_id, &1)) |> Enum.take(@public_shown),
      page: page(fleet_id, board.projects),
      season: SeasonPanel.face(fleet_id)
    }
  end

  defp public(fleet_id, record) do
    case record |> words() |> clipped() do
      "" ->
        []

      title ->
        [
          %{
            id: record.id,
            kind: kind(record),
            title: title,
            key: ActivityLines.key_name(record.key, nil),
            link: WorkspacePage.place_path(fleet_id, :public) <> "#public-" <> record.id
          }
        ]
    end
  end

  # The kind as the Public place names it.
  defp kind(%{kind: :item, item: item}),
    do: item.type |> WorkspacePage.type_name() |> elem(0) |> String.capitalize()

  defp kind(%{kind: :posts}), do: "Posts"
  defp kind(%{kind: :page}), do: "Notebook page"
  defp kind(%{kind: :commit}), do: "Code"

  defp words(%{kind: :item, item: item}), do: item.title
  defp words(%{kind: :posts, posts: [first | _]}), do: ActivityLines.plain(first.body)
  defp words(%{kind: :posts, posts: []}), do: nil
  defp words(%{kind: kind, label: label}) when kind in [:page, :commit], do: label

  # On one line, and at most `@title_length` characters: one longer ends on
  # its last whole word that fits, with "…" for the rest. No words is "".
  defp clipped(nil), do: ""

  defp clipped(words) do
    line = words |> String.split() |> Enum.join(" ")

    if String.length(line) <= @title_length do
      line
    else
      cut = String.slice(line, 0, @title_length - 1)

      whole =
        if String.at(line, @title_length - 1) == " ",
          do: cut,
          else: String.replace(cut, ~r/ \S*\z/u, "")

      String.replace(whole, ~r/[.,;:]+\z/u, "") <> "…"
    end
  end

  defp page(fleet_id, projects) do
    titles = Map.new(projects, &{&1.name, &1.title})

    case Projects.publications!(fleet_id, nil,
           query: [filter: [kind: :page, project: [in: Map.keys(titles)]], limit: 1]
         ) do
      [newest] ->
        %{
          title: clipped(titles[newest.project]),
          key: ActivityLines.key_name(newest.key, nil),
          url: Notebooks.url(fleet_id, newest.page)
        }

      [] ->
        nil
    end
  end

  defp minted!(fleet_id) do
    case Chain.minted(fleet_id) do
      {:ok, minted} -> minted
      {:error, failure} -> raise failure
    end
  end

  defp goal(fleet_id) do
    case Graph.open_goals!(fleet_id, query: [limit: 1]) do
      [goal] -> goal.title
      [] -> nil
    end
  end
end
