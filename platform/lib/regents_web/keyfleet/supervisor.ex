defmodule RegentsWeb.Keyfleet.Supervisor do
  @moduledoc """
  Keyfleet's shared readings on the page side, each read once for every open
  page: what each fleet is doing now (`RegentsWeb.Keyfleet.FleetNow`) and its
  proposal pages (`RegentsWeb.Keyfleet.FleetProposals`). Each reads the one
  database, rereads on notice, and writes only its reading
  (`Regents.SharedReading`) and the site's errors. `Regents.Application`
  starts it only where pages are served, after `Regents.Keyfleet.Supervisor`,
  under which their failed reads are saved (`RegentsWeb.Keyfleet.PageRead`).
  """
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Supervisor.init([RegentsWeb.Keyfleet.FleetNow, RegentsWeb.Keyfleet.FleetProposals],
      strategy: :one_for_one
    )
  end
end
