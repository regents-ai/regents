defmodule Regents.Staking.SnapshotListener do
  @moduledoc """
  Passes shared database refresh notices to this machine's staking pages, heard on
  the site's listening connection (`Regents.SharedChanges`).
  """

  use GenServer
  alias Regents.Staking.SnapshotCache

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    # Listening starts now, or as soon as the connection is up.
    {_now_or_on_connect, ref} =
      Postgrex.Notifications.listen(Regents.Notifications, SnapshotCache.channel())

    {:ok, ref}
  end

  @impl true
  def handle_info(
        {:notification, _connection, ref, _channel, "updated"},
        ref
      ) do
    if snapshot = SnapshotCache.snapshot() do
      Phoenix.PubSub.broadcast(
        Regents.PubSub,
        SnapshotCache.topic(),
        {:staking_snapshot, snapshot}
      )
    end

    {:noreply, ref}
  end

  def handle_info(
        {:notification, _connection, ref, _channel, "unavailable"},
        ref
      ) do
    Phoenix.PubSub.broadcast(
      Regents.PubSub,
      SnapshotCache.topic(),
      {:staking_snapshot_unavailable, :unavailable}
    )

    {:noreply, ref}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
