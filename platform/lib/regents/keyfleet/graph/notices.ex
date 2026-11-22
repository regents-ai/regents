defmodule Regents.Keyfleet.Graph.Notices do
  @moduledoc """
  The projectors' two notices, carried from the graph machine to the site
  through the database. A projector sends each with `pg_notify` once what it
  announces is committed (`head/3`, `notable/1`), and this process, on the site
  machine, hears them on the site's own `Regents.Notifications` connection
  and repeats each on this machine's PubSub, on the topic and in the shape the
  pages already wait for: `{:graph_head, fleet_id, run_id, watermark}` on
  `Regents.Keyfleet.Graph.head_topic/1` and `{:graph_notable, fleet_id}` on
  `Regents.Keyfleet.Graph.notable_topic/1`. It starts after that connection, under
  `Regents.SharedChanges`, as `RegentAgents.Listener` does.

  A notice is only a hint to read again, so one that cannot be sent is logged
  and skipped. Every site shares the database, so the channels carry
  Keyfleet's name, and a notice, a fleet id and a log's place, stays far
  below PostgreSQL's 8,000-byte limit.
  """

  use GenServer

  require Logger

  alias Regents.Keyfleet.Graph

  @head "keyfleet_graph_head"
  @notable "keyfleet_graph_notable"

  @doc "Says that the fleet's read tables reached `watermark` in the log `run_id`."
  @spec head(String.t(), String.t(), non_neg_integer()) :: :ok
  def head(fleet_id, run_id, watermark),
    do: notify(@head, Jason.encode!(%{fleet_id: fleet_id, run_id: run_id, watermark: watermark}))

  @doc "Says that the fleet's activity has a new workspace change to show."
  @spec notable(String.t()) :: :ok
  def notable(fleet_id), do: notify(@notable, fleet_id)

  defp notify(channel, payload) do
    case Ecto.Adapters.SQL.query(Regents.Repo, "SELECT pg_notify($1, $2)", [channel, payload]) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        Logger.warning("a graph notice on #{channel} was not sent: " <> Exception.message(error))
    end
  end

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    # Listening starts now, or as soon as the connection is up.
    for channel <- [@head, @notable],
        do:
          {_now_or_on_connect, _ref} =
            Postgrex.Notifications.listen(Regents.Notifications, channel)

    {:ok, nil}
  end

  @impl true
  def handle_info({:notification, _connection, _ref, @head, payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"fleet_id" => fleet_id, "run_id" => run_id, "watermark" => watermark}}
      when is_binary(fleet_id) and is_binary(run_id) and is_integer(watermark) ->
        broadcast(Graph.head_topic(fleet_id), {:graph_head, fleet_id, run_id, watermark})

      # A notice is only a hint to read again, whoever sent it: any role on
      # the shared database may notify, every head notice of this shape is
      # passed on, and every notable notice too, unchecked. A head notice of
      # another shape is dropped.
      _other ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info({:notification, _connection, _ref, @notable, fleet_id}, state) do
    broadcast(Graph.notable_topic(fleet_id), {:graph_notable, fleet_id})
    {:noreply, state}
  end

  defp broadcast(topic, message), do: Phoenix.PubSub.broadcast(Regents.PubSub, topic, message)
end
