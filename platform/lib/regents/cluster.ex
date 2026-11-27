defmodule Regents.Cluster do
  @moduledoc """
  Lightweight Fly 6PN Erlang cluster peer discovery.

  When running on Fly.io (`FLY_APP_NAME` and `FLY_PRIVATE_IP` set and the node
  is distributed), polls `<app>.internal` AAAA DNS records every 15 seconds and
  connects to sibling machines with `Node.connect/1`. This lets `Regents.PubSub`,
  `Regents.ProductActivity`, `Regents.SharedReading`, and Keyfleet's cross-node
  SSE feed replacement work cleanly under `fly scale count 2` with zero external
  dependencies.
  """

  use GenServer

  require Logger

  @poll_interval_ms :timer.seconds(15)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # `app` is the fixed FLY_APP_NAME environment variable and each IP comes from
  # Fly's private 6PN `<app>.internal` AAAA DNS lookup, never user input.
  # sobelow_skip ["DOS.BinToAtom"]
  @doc "Resolves Fly internal AAAA peers for `app` into distributed node atoms."
  @spec discover_peers(String.t()) :: [node()]
  def discover_peers(app) when is_binary(app) and app != "" do
    query = String.to_charlist("#{app}.internal")

    query
    |> :inet_res.lookup(:in, :aaaa)
    |> Enum.map(fn ip ->
      ip_str = ip |> :inet.ntoa() |> List.to_string()
      :"#{app}@#{ip_str}"
    end)
    |> Enum.reject(&(&1 == Node.self()))
  rescue
    _ -> []
  end

  @impl true
  def init(opts) do
    app = Keyword.get(opts, :app, System.get_env("FLY_APP_NAME", ""))
    interval = Keyword.get(opts, :interval_ms, @poll_interval_ms)

    if Node.alive?() and app != "" do
      send(self(), :discover)
      {:ok, %{app: app, interval_ms: interval}}
    else
      {:ok, %{app: nil, interval_ms: interval}}
    end
  end

  @impl true
  def handle_info(:discover, %{app: app, interval_ms: interval} = state) when is_binary(app) do
    connected = MapSet.new(Node.list())

    for peer <- discover_peers(app), not MapSet.member?(connected, peer) do
      case Node.connect(peer) do
        true -> Logger.info("Connected to cluster peer #{peer}")
        _ -> :ok
      end
    end

    Process.send_after(self(), :discover, interval)
    {:noreply, state}
  end

  def handle_info(:discover, state), do: {:noreply, state}
end
