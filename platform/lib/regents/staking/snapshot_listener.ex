defmodule Regents.Staking.SnapshotListener do
  @moduledoc "Passes shared database refresh notices to this machine's staking pages."

  use GenServer
  alias Regents.Staking.SnapshotCache

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    {:ok, connection} =
      Regents.Repo.config()
      |> Keyword.drop([:name, :pool, :pool_size])
      |> Keyword.put(:auto_reconnect, true)
      |> Postgrex.Notifications.start_link()

    {_listening, ref} = Postgrex.Notifications.listen(connection, SnapshotCache.channel())
    {:ok, {connection, ref}}
  end

  @impl true
  def handle_info(
        {:notification, connection, ref, _channel, "updated"},
        {connection, ref} = state
      ) do
    if snapshot = SnapshotCache.snapshot() do
      Phoenix.PubSub.broadcast(
        Regents.PubSub,
        SnapshotCache.topic(),
        {:staking_snapshot, snapshot}
      )
    end

    {:noreply, state}
  end

  def handle_info(
        {:notification, connection, ref, _channel, "unavailable"},
        {connection, ref} = state
      ) do
    Phoenix.PubSub.broadcast(
      Regents.PubSub,
      SnapshotCache.topic(),
      {:staking_snapshot_unavailable, :unavailable}
    )

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
