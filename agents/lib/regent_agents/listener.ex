defmodule RegentAgents.Listener do
  @moduledoc """
  Hears agent changes from every Regent site through the shared database and
  passes each one to this site's PubSub, as `:agents_changed` on
  `RegentAgents.topic/1`. A site starts one after its repository and PubSub.
  It holds one database connection of its own, and reconnects on its own if
  that connection drops.
  """

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    repo = Application.fetch_env!(:regent_agents, :repo)

    {:ok, notifications} =
      repo.config()
      |> Keyword.drop([:name, :pool, :pool_size])
      |> Keyword.put(:auto_reconnect, true)
      |> Postgrex.Notifications.start_link()

    # Listening starts now, or as soon as the connection is up.
    {_now_or_on_connect, _ref} =
      Postgrex.Notifications.listen(notifications, RegentAgents.channel())

    {:ok, Application.fetch_env!(:regent_agents, :pubsub)}
  end

  @impl true
  def handle_info({:notification, _notifications, _ref, _channel, privy_user_id}, pubsub) do
    Phoenix.PubSub.broadcast(pubsub, RegentAgents.topic(privy_user_id), :agents_changed)
    {:noreply, pubsub}
  end
end
