defmodule Regents.Autolaunch.Supervisor do
  @moduledoc """
  Autolaunch's place in the site's supervision tree. It reads the deployment
  descriptions as it starts (`Regents.Autolaunch.load_deployments!/0`), so a
  malformed one stops the site's start, as it stopped autolaunch.sh's, and
  every later read is answered from memory. It has no children yet:
  Autolaunch's readers and caches join it with the pages that show them.
  """
  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ok = Regents.Autolaunch.load_deployments!()
    Supervisor.init([], strategy: :one_for_one)
  end
end
