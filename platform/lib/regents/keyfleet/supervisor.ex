defmodule Regents.Keyfleet.Supervisor do
  @moduledoc """
  Keyfleet's processes that run here: only those that keep what they are
  given in memory, read nothing outside the one database and PubSub, and write
  nothing. So far that is the access cache (`Regents.Keyfleet.AccessCache`):
  who was let into a fleet's notebooks or code lately, cleared at once through
  PubSub when a Key changes hands. `Regents.Application` starts it after PubSub
  and `Regents.SharedReading`. Keyfleet's other processes come with the slice
  that starts them (`SOURCE.json`, `not_started`).
  """
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil), do: Supervisor.init([Regents.Keyfleet.AccessCache], strategy: :one_for_one)
end
