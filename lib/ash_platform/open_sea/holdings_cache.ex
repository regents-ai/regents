defmodule AshPlatform.OpenSea.HoldingsCache do
  @moduledoc false
  use GenServer

  @call_timeout 17_000
  @default_ttl_ms 15_000
  @max_entries 512

  def start_link(_options), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def fetch(address, loader) when is_binary(address) and is_function(loader, 0),
    do: GenServer.call(__MODULE__, {:fetch, address, loader}, @call_timeout)

  @doc false
  def clear, do: GenServer.call(__MODULE__, :clear)

  def invalidate(address) when is_binary(address),
    do: GenServer.call(__MODULE__, {:invalidate, address})

  @impl true
  def init(_), do: {:ok, %{cache: %{}, in_flight: %{}, retired: %{}}}

  @impl true
  def handle_call(:clear, _from, state), do: {:reply, :ok, %{state | cache: %{}}}

  def handle_call({:invalidate, address}, _from, state) do
    {lookup, in_flight} = Map.pop(state.in_flight, address)

    retired =
      case lookup do
        %{ref: ref, waiters: waiters} -> Map.put(state.retired, ref, waiters)
        nil -> state.retired
      end

    {:reply, :ok,
     %{
       state
       | cache: Map.delete(state.cache, address),
         in_flight: in_flight,
         retired: retired
     }}
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
  def handle_info({:loaded, address, ref, result}, state) do
    case state.in_flight[address] do
      %{ref: ^ref, waiters: waiters} ->
        Enum.each(waiters, &GenServer.reply(&1, result))

        cache =
          case result do
            {:ok, _holdings} -> cache_result(state.cache, address, result)
            _ -> state.cache
          end

        {:noreply, %{state | cache: cache, in_flight: Map.delete(state.in_flight, address)}}

      _ ->
        reply_retired(ref, result, state)
    end
  end

  defp safely_load(loader) do
    loader.()
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp join_or_start(address, loader, from, state) do
    case state.in_flight[address] do
      %{waiters: waiters} = lookup ->
        in_flight = Map.put(state.in_flight, address, %{lookup | waiters: [from | waiters]})
        {:noreply, %{state | in_flight: in_flight}}

      nil ->
        ref = make_ref()
        server = self()
        spawn(fn -> send(server, {:loaded, address, ref, safely_load(loader)}) end)

        in_flight = Map.put(state.in_flight, address, %{ref: ref, waiters: [from]})
        {:noreply, %{state | in_flight: in_flight}}
    end
  end

  defp reply_retired(ref, result, state) do
    case Map.pop(state.retired, ref) do
      {nil, _retired} ->
        {:noreply, state}

      {waiters, retired} ->
        Enum.each(waiters, &GenServer.reply(&1, result))
        {:noreply, %{state | retired: retired}}
    end
  end

  defp cache_result(cache, address, result) do
    ttl = Application.get_env(:ash_platform, :opensea_holdings_cache_ttl_ms, @default_ttl_ms)
    expires_at = System.monotonic_time(:millisecond) + max(ttl, 0)

    cache
    |> Map.put(address, {expires_at, result})
    |> Enum.sort_by(fn {_address, {expires, _result}} -> expires end, :desc)
    |> Enum.take(@max_entries)
    |> Map.new()
  end

  defp prune(cache, now) do
    Map.reject(cache, fn {_address, {expires_at, _result}} -> expires_at <= now end)
  end
end
