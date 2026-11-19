defmodule RegentPoints.PubSub do
  @moduledoc false
  def broadcast(_name, topic, message) do
    Phoenix.PubSub.broadcast(Application.fetch_env!(:regent_points, :pubsub), topic, message)
  end
end
