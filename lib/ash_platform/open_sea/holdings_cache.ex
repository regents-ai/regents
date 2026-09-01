defmodule AshPlatform.OpenSea.HoldingsCache do
  @moduledoc false
  use GenServer

  @call_timeout 17_000
  @default_ttl_ms 15_000
  @default_max_in_flight 4
  @max_entries 512

  def start_link(_options), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def fetch(address, loader) when is_binary(address) and is_function(loader, 0),
    do: GenServer.call(__MODULE__, {:fetch, address, loader}, @call_timeout)

  @doc false
  def clear, do: GenServer.call(__MODULE__, :clear)

  def invalidate(address) when is_binary(address),
    do: GenServer.call(__MODULE__, {:invalidate, address})

  @impl true
  def init(_), do: {:ok, empty()}

  @impl true
  # Resetting abandons every read in flight, so the pages waiting on one are told
  # the lookup is unavailable rather than left holding a call nothing will answer.
  def handle_call(:clear, _from, state) do
    Enum.each(state.in_flight, fn {_address, %{monitor: monitor, waiters: waiters}} ->
      Process.demonitor(monitor, [:flush])
      Enum.each(waiters, &GenServer.reply(&1, {:error, :unavailable}))
    end)

    {:reply, :ok, empty()}
  end

  # An address may be invalidated once per cache window. A page that just watched
  # a redemption confirm gets the fresh read it needs, while a page repeating the
  # same request only ever gets the one read the window already allowed.
  def handle_call({:invalidate, address}, _from, state) do
    now = System.monotonic_time(:millisecond)
    cooldowns = prune(state.cooldowns, now)

    if Map.has_key?(cooldowns, address),
      do: {:reply, :ok, %{state | cooldowns: cooldowns}},
      else: {:reply, :ok, forget(state, address, cooldowns, now)}
  end

  def handle_call({:fetch, address, loader}, from, state) do
    now = System.monotonic_time(:millisecond)
    cache = prune(state.cache, now)

    case cache[address] do
      {expires_at, result} when expires_at > now ->
        {:reply, result, %{state | cache: cache}}

      _ ->
        join_or_start(address, loader, from, %{state | cache: cache})
    end
  end

  @impl true
  def handle_info({:loaded, address, pid, result}, state) do
    case state.in_flight[address] do
      %{pid: ^pid, monitor: monitor, waiters: waiters, stale: stale} ->
        Process.demonitor(monitor, [:flush])
        Enum.each(waiters, &GenServer.reply(&1, result))

        cache =
          case {stale, result} do
            {false, {:ok, _holdings}} -> cache_result(state.cache, address, result)
            _ -> state.cache
          end

        {:noreply, %{state | cache: cache, in_flight: Map.delete(state.in_flight, address)}}

      _ ->
        {:noreply, state}
    end
  end

  # A loader can die without answering: the OpenSea read runs linked tasks, and a
  # crash in one of them takes the loader with it. Its slot is released and its
  # waiters are told the lookup is unavailable, so a dead read never costs the
  # server a live-read slot for good.
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Enum.find(state.in_flight, fn {_address, lookup} -> lookup.monitor == monitor end) do
      {address, %{waiters: waiters}} ->
        Enum.each(waiters, &GenServer.reply(&1, {:error, :unavailable}))
        {:noreply, %{state | in_flight: Map.delete(state.in_flight, address)}}

      nil ->
        {:noreply, state}
    end
  end

  defp empty, do: %{cache: %{}, in_flight: %{}, cooldowns: %{}}

  defp safely_load(loader) do
    loader.()
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  # Waiting on one address costs nothing beyond the read already running, so a
  # joiner is always welcome, except on a read that started before the address
  # was invalidated: that answer is exactly the one the invalidation said not to
  # trust, so the page is told the lookup is unavailable instead of being handed
  # a collection that predates its own redemption. A new address is only worth a
  # loader while the server is under its live-read ceiling; past it the page is
  # told the lookup is unavailable rather than left queued behind reads it cannot
  # see.
  defp join_or_start(address, loader, from, state) do
    case state.in_flight[address] do
      %{stale: true} ->
        {:reply, {:error, :unavailable}, state}

      %{waiters: waiters} = lookup ->
        in_flight = Map.put(state.in_flight, address, %{lookup | waiters: [from | waiters]})
        {:noreply, %{state | in_flight: in_flight}}

      nil ->
        if map_size(state.in_flight) >= max_in_flight() do
          {:reply, {:error, :unavailable}, state}
        else
          {:noreply, %{state | in_flight: start_load(state.in_flight, address, loader, from)}}
        end
    end
  end

  defp start_load(in_flight, address, loader, from) do
    server = self()

    {pid, monitor} =
      spawn_monitor(fn -> send(server, {:loaded, address, self(), safely_load(loader)}) end)

    Map.put(in_flight, address, %{pid: pid, monitor: monitor, waiters: [from], stale: false})
  end

  # A read that is still running answered from before the invalidation, so its
  # result is no longer worth remembering. It keeps its live-read slot until it
  # actually ends: a slot the server has not got back is not a slot to hand out.
  defp forget(state, address, cooldowns, now) do
    %{
      state
      | cache: Map.delete(state.cache, address),
        in_flight: mark_stale(state.in_flight, address),
        cooldowns: remember(cooldowns, address, {now + ttl(), :invalidated})
    }
  end

  defp mark_stale(in_flight, address) do
    case in_flight[address] do
      nil -> in_flight
      lookup -> Map.put(in_flight, address, %{lookup | stale: true})
    end
  end

  defp cache_result(cache, address, result),
    do: remember(cache, address, {System.monotonic_time(:millisecond) + ttl(), result})

  defp remember(entries, address, entry) do
    entries = Map.put(entries, address, entry)

    if map_size(entries) <= @max_entries,
      do: entries,
      else:
        entries
        |> Enum.sort_by(fn {_address, {expires_at, _value}} -> expires_at end, :desc)
        |> Enum.take(@max_entries)
        |> Map.new()
  end

  defp prune(entries, now) do
    Map.reject(entries, fn {_address, {expires_at, _value}} -> expires_at <= now end)
  end

  defp ttl,
    do:
      max(
        Application.get_env(:ash_platform, :opensea_holdings_cache_ttl_ms, @default_ttl_ms),
        0
      )

  defp max_in_flight,
    do:
      Application.get_env(:ash_platform, :opensea_holdings_max_in_flight, @default_max_in_flight)
end
