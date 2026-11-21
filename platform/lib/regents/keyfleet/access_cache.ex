defmodule Regents.Keyfleet.AccessCache do
  @moduledoc """
  Who was let into one of a fleet's private places lately (`:notebooks`,
  `:code`), so its gateway checks key ownership at most once in that place's
  time for each of them, and who was made an editor of the fleet's hub
  projects (`:hub_editor`), so the hub is not asked again. Only a yes is
  kept, with what the check found.

  `end_access/3` clears one subject at once and `end_fleet/2` everyone in one
  place of a fleet, on this machine only; this process owns the table and
  hears both. While a release runs two site machines, the other one keeps
  what it let in until it checks again or stops: within `access_ttl_ms` (30
  seconds) for notebooks and code, `editor_ttl_ms` (10 minutes) for a hub
  editor.
  """
  use GenServer

  @table __MODULE__
  @topic "keyfleet:fleet_access"

  def start_link(_options), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "What was found when `subject` was last let into `place` of the fleet, while it still holds: `{:ok, found}` or `:none`."
  def lookup(place, fleet_id, subject) do
    case :ets.lookup(@table, {place, fleet_id, subject}) do
      [{_key, until, found}] -> if until > now(), do: {:ok, found}, else: :none
      [] -> :none
    end
  end

  @doc "Records that `subject` was just let into `place` of the fleet, for `ttl_ms`."
  def admit(place, fleet_id, subject, found, ttl_ms) do
    :ets.insert(@table, {{place, fleet_id, subject}, now() + ttl_ms, found})
    :ok
  end

  @doc "Ends `subject`'s admission to `place` of the fleet on this machine now."
  def end_access(place, fleet_id, subject),
    do: Phoenix.PubSub.broadcast(Regents.PubSub, @topic, {:end_access, place, fleet_id, subject})

  @doc "Ends everyone's admission to `place` of the fleet on this machine now."
  def end_fleet(place, fleet_id),
    do: Phoenix.PubSub.broadcast(Regents.PubSub, @topic, {:end_fleet, place, fleet_id})

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ok = Phoenix.PubSub.subscribe(Regents.PubSub, @topic)
    {:ok, nil}
  end

  @impl GenServer
  def handle_info({:end_access, place, fleet_id, subject}, state) do
    :ets.delete(@table, {place, fleet_id, subject})
    {:noreply, state}
  end

  def handle_info({:end_fleet, place, fleet_id}, state) do
    :ets.match_delete(@table, {{place, fleet_id, :_}, :_, :_})
    {:noreply, state}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
