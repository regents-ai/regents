defmodule Regents.Keyfleet.Agents.Here do
  @moduledoc """
  The agents here in each fleet and what their check-ins say, read once for
  every open page and held in `Regents.SharedReading`. One runs on each
  machine.

  Two readings come from each pass over a fleet:

    * `fleet_key/1`: "Here now", the count of agents, the bar's count of
      the addresses holding a Key and of those online now
      (`Regents.Keyfleet.Keys.count_holders/2`, over the last hour), and as many of
      the agents as the fleet's directory lists, each with what its check-ins
      say (its light, the light's meaning and its two lines, `seen_by/2`), the id
      that names its row and the address of its own picture, or nil when it
      set none: a picture made from its wallet is made where it is drawn
      (`Regents.Keyfleet.Agents.Avatar.shown/2`), and is ten times the size of the
      address. The wallet is never written into the page. Beside them,
      `faces`: who holds each of their Keys, the Key they write as and how
      many of the fleet's Keys they hold (`Regents.Keyfleet.Keys.faces/2`), for the city's
      discs.
    * `lines_key/2`: what each agent's check-ins say, by wallet, for the open
      Key.

  A Key holds the second only while it has an active shard, and up to as
  many shards as a Key's page lists.

  This is a reread on notice, the second of the two shapes the `elixir-stack`
  skill lets keep a shared reading. It hears every `{:keys_changed, ...}` of the
  fleets (a shard issued or ended sends one) and reads that fleet again, at most
  once a second however many arrive. It holds nothing but which fleets are due a
  read, and it never writes the database.

  A status ages with the clock, and a check-in tells only its person's pages, so each minute
  `Regents.SharedReading.Heal` asks for every fleet to be read again. The words
  ("Seen 3 minutes ago") are written here with one moment for the
  whole pass, never on the page, so a page wakes only when what it shows has
  changed (`ash-frontend`, `references/public-figures.md`).

  The first read happens as it starts, so each fleet holds a reading or its
  degraded mark before the site serves a page.
  """

  use GenServer

  alias Regents.Keyfleet.{Agents, Directory, Fleets, Keys}
  alias Regents.Keyfleet.Agents.{Avatar, CheckInStatus}
  alias Regents.ProductActivity
  alias Regents.SharedReading

  # As many of a Key's agents as its page lists (`Regents.Keyfleet.Keys.Profile`).
  @listed 100

  @kinds [:keyfleet_fleet_agents, :keyfleet_key_agents]

  @did %{
    post: "posted",
    task: "took a task",
    submit: "handed in a task",
    review: "reviewed",
    workspace: "worked",
    notebook: "edited a notebook",
    code: "pushed code"
  }

  @doc "Where \"Here now\" for `fleet_id` is held."
  def fleet_key(fleet_id), do: {:keyfleet_fleet_agents, fleet_id}

  @doc "Where what the check-ins of the agents on one Key say is held."
  def lines_key(fleet_id, token_id), do: {:keyfleet_key_agents, "#{fleet_id}:#{token_id}"}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(nil) do
    Enum.each(@kinds, fn kind ->
      SharedReading.register_producer(kind, self(), :sync)
      SharedReading.subscribe_heal(kind)
    end)

    ProductActivity.subscribe()

    for fleet_id <- Fleets.catalog_ids(),
        do: Phoenix.PubSub.subscribe(Regents.PubSub, Keys.topic(fleet_id))

    {:ok, %{due: MapSet.new(), loaded?: false}}
  end

  @impl true
  def handle_call(:ensure_loaded, _from, %{loaded?: true} = state), do: {:reply, :ok, state}

  def handle_call(:ensure_loaded, _from, state) do
    ProductActivity.touch(:keyfleet)
    read_fleets(Fleets.catalog_ids())
    Enum.each(@kinds, &SharedReading.mark_loaded(&1, true))
    {:reply, :ok, %{state | due: MapSet.new(), loaded?: true}}
  end

  @impl true
  def handle_info({:product_idle, :keyfleet}, %{loaded?: true} = state) do
    Enum.each(@kinds, fn kind ->
      SharedReading.mark_loaded(kind, false)
      SharedReading.clear_kind(kind)
    end)

    {:noreply, %{state | due: MapSet.new(), loaded?: false}}
  end

  def handle_info({:product_idle, _product}, state), do: {:noreply, state}
  def handle_info({:product_active, _product}, state), do: {:noreply, state}

  def handle_info({:keys_changed, fleet_id, _token_ids}, %{loaded?: true} = state),
    do: {:noreply, due(state, fleet_id)}

  def handle_info({:keys_changed, _fleet_id, _token_ids}, state), do: {:noreply, state}

  # Keys marked present change no agent's line here.
  def handle_info({:keys_present, _fleet_id, _token_ids}, state), do: {:noreply, state}

  def handle_info({:shared_reading_heal, _kind}, %{loaded?: true} = state) do
    if ProductActivity.active?(:keyfleet),
      do: {:noreply, Enum.reduce(Fleets.catalog_ids(), state, &due(&2, &1))},
      else: {:noreply, state}
  end

  def handle_info({:shared_reading_heal, _kind}, state), do: {:noreply, state}

  def handle_info(:read, %{loaded?: true} = state) do
    if MapSet.size(state.due) > 0 and ProductActivity.active?(:keyfleet),
      do: read_fleets(state.due)

    {:noreply, %{state | due: MapSet.new()}}
  end

  def handle_info(:read, state), do: {:noreply, %{state | due: MapSet.new()}}

  # The first fleet to fall due starts the one-second wait; the rest join it.
  defp due(state, fleet_id) do
    if MapSet.size(state.due) == 0, do: Process.send_after(self(), :read, 1_000)
    %{state | due: MapSet.put(state.due, fleet_id)}
  end

  # Reads the fleets table once per pass and skips undeployed coming-soon fleets.
  defp read_fleets(fleet_ids) do
    case recorded_fleets() do
      {:ok, recorded} ->
        Enum.each(fleet_ids, &read(&1, Map.get(recorded, &1)))

      :error ->
        Enum.each(fleet_ids, &mark_degraded/1)
    end
  end

  defp recorded_fleets do
    case Fleets.list_fleets() do
      {:ok, fleets} -> {:ok, Map.new(fleets, &{&1.id, &1})}
      {:error, _failure} -> :error
    end
  rescue
    Ash.Error.Unknown -> :error
    DBConnection.ConnectionError -> :error
    Postgrex.Error -> :error
  end

  defp mark_degraded(fleet_id) do
    SharedReading.degraded(fleet_key(fleet_id))
    for id <- held(fleet_id), do: SharedReading.degraded({:keyfleet_key_agents, id})
  end

  @doc """
  Reads `fleet_id`'s agents and puts its two kinds of reading, deleting the
  Keys no agent works on any more. What the producer runs on each pass.
  """
  def read(fleet_id) do
    case Fleets.get_fleet(fleet_id) do
      {:ok, recorded} -> read(fleet_id, recorded)
      {:error, _failure} -> mark_degraded(fleet_id)
    end
  rescue
    Ash.Error.Unknown -> mark_degraded(fleet_id)
    DBConnection.ConnectionError -> mark_degraded(fleet_id)
    Postgrex.Error -> mark_degraded(fleet_id)
  end

  defp read(fleet_id, recorded) do
    if Fleets.coming_soon?(fleet_id, recorded) do
      SharedReading.put(fleet_key(fleet_id), %{
        here: 0,
        agents: [],
        holders: %{holders: 0, online: 0},
        faces: %{}
      })

      for id <- held(fleet_id), do: SharedReading.delete({:keyfleet_key_agents, id})
      :ok
    else
      now = DateTime.utc_now()
      read_here(fleet_id, now)
      read_keys(fleet_id, now)
    end
  end

  defp read_here(fleet_id, now) do
    case here(fleet_id, now) do
      {:ok, reading} -> SharedReading.put(fleet_key(fleet_id), reading)
      {:error, _not_read} -> SharedReading.degraded(fleet_key(fleet_id))
    end
  end

  defp here(fleet_id, now) do
    agents =
      for profile <- Agents.agents_here!(fleet_id, query: [limit: Directory.agents_shown()]) do
        %{
          id: profile.id,
          name: profile.name,
          avatar_url: Avatar.url(profile),
          key: profile.key,
          wallet_address: profile.wallet_address,
          seen: seen(List.first(profile.check_ins), now)
        }
      end

    count =
      case Agents.count_agents_here(fleet_id) do
        {:ok, count} -> count
        {:error, _failure} -> nil
      end

    holders =
      case Keys.count_holders(fleet_id, DateTime.add(now, -1, :hour)) do
        {:ok, holders} -> holders
        {:error, _failure} -> nil
      end

    keys = for %{key: token_id} <- agents, is_integer(token_id), uniq: true, do: token_id

    {:ok,
     %{
       here: count,
       agents: agents,
       holders: holders,
       faces: Keys.faces(fleet_id, keys)
     }}
  rescue
    # The database not answering raises beneath Ash. It is a read not taken,
    # never a reason for this process, and the site with it, to stop.
    error in [Ash.Error.Unknown, DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end

  defp read_keys(fleet_id, now) do
    case on_keys(fleet_id, now) do
      {:ok, by_key} ->
        Enum.each(by_key, fn {token_id, shards} -> put_key(fleet_id, token_id, shards) end)
        kept = MapSet.new(by_key, fn {token_id, _shards} -> "#{fleet_id}:#{token_id}" end)

        for id <- held(fleet_id),
            id not in kept,
            do: SharedReading.delete({:keyfleet_key_agents, id})

      {:error, _not_read} ->
        for id <- held(fleet_id),
            do: SharedReading.degraded({:keyfleet_key_agents, id})
    end
  end

  defp put_key(fleet_id, token_id, shards) do
    SharedReading.put(
      lines_key(fleet_id, token_id),
      for({wallet, %{} = seen} <- shards, do: {wallet, seen})
    )
  end

  # The trailing ":" keeps one fleet's ids from matching another's.
  defp held(fleet_id),
    do:
      Enum.filter(
        SharedReading.ids(:keyfleet_key_agents),
        &String.starts_with?(&1, fleet_id <> ":")
      )

  # Every active shard in the fleet by Key, each with the agent that signed in
  # with it, if one has, and what its check-ins with the fleet say.
  defp on_keys(fleet_id, now) do
    shards = Keys.active_shards_in_fleet!(fleet_id, load: [:agent_profile])

    check_ins =
      for(%{agent_profile: %{id: id}} <- shards, uniq: true, do: id)
      |> Enum.chunk_every(100)
      |> Enum.flat_map(&Agents.check_ins_in_fleet!(fleet_id, &1))
      |> Map.new(&{&1.agent_profile_id, &1})

    {:ok,
     shards
     |> Enum.group_by(& &1.token_id, &{&1.wallet, agent(&1.agent_profile, check_ins, now)})
     |> Map.new(fn {token_id, shards} -> {token_id, Enum.take(shards, @listed)} end)}
  rescue
    error in [Ash.Error.Unknown, DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end

  defp agent(nil, _check_ins, _now), do: nil

  defp agent(profile, check_ins, now), do: seen(check_ins[profile.id], now)

  @doc """
  What one agent's check-ins say to a reader: its light, what the light
  means, and one short line. A member of the fleet reads when the agent was
  last seen, what it last did and how many times it came back on its own
  schedule; anyone else reads when it was last active and how many times it
  came back, since what it did may be in the fleet's own places.
  """
  def seen_by(%{members_line: members_line} = seen, true),
    do: seen |> Map.delete(:members_line) |> Map.put(:line, members_line)

  def seen_by(seen, false), do: Map.delete(seen, :members_line)

  # Both lines are written once for the whole pass; each page picks its
  # reader's with `seen_by/2`.
  defp seen(check_in, now) do
    {_status, label} = CheckInStatus.derive(check_in, now)

    %{
      light: CheckInStatus.light(check_in, now),
      label: label,
      line: line(check_in, now, &active/2),
      members_line: line(check_in, now, &last/2)
    }
  end

  defp line(nil, _now, _last), do: "Not seen yet"

  defp line(check_in, now, last),
    do: last.(check_in, now) <> returns(check_in.scheduled_check_ins)

  defp active(check_in, now),
    do: "Active #{RegentFormat.relative_time(check_in.last_seen_at, now)}"

  # A contribution after the last check-in is when it was seen.
  defp last(%{last_contribution_at: at, last_seen_at: at} = check_in, now),
    do: upcase_first(contributed(check_in.last_contribution_kind, at, now))

  defp last(%{last_contribution_at: nil} = check_in, now),
    do: "Seen #{RegentFormat.relative_time(check_in.last_seen_at, now)}"

  defp last(check_in, now) do
    "Seen #{RegentFormat.relative_time(check_in.last_seen_at, now)} · " <>
      contributed(check_in.last_contribution_kind, check_in.last_contribution_at, now)
  end

  defp contributed(kind, at, now), do: "#{@did[kind]} #{RegentFormat.relative_time(at, now)}"

  defp returns(0), do: ""
  defp returns(1), do: " · came back once"
  defp returns(times), do: " · came back #{times} times"

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
end
