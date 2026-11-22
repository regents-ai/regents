defmodule Regents.Keyfleet.Supervisor do
  @moduledoc """
  Keyfleet's processes that run here: only those that keep what they are
  given in memory, read nothing outside the one database, PubSub and the
  chain a press's steps are read from, and write nothing but the site's
  errors. They are the task supervisor `Regents.Keyfleet.ErrorSaves`, under
  which a failure a page read rescued (`RegentsWeb.Keyfleet.PageRead`), or a
  press's build raised (`RegentsWeb.Keyfleet.WalletPanel`), is saved beside
  the page (past twenty at once, a failure is only
  logged); the task supervisor `Regents.Keyfleet.PressBuilds`, under which
  the steps a press on a wallet button asks for are built
  (`RegentsWeb.Keyfleet.WalletPanel`), with no cap: a page's own process
  runs one build at a time and each build is bounded, so there are never
  more of these tasks than open pages; the access cache
  (`Regents.Keyfleet.AccessCache`): who was let into a fleet's notebooks or
  code lately, cleared at once through PubSub when a Key changes hands; the
  keep of what waits for each Key's holder
  (`Regents.Keyfleet.Chain.RewardsWaiting`), a table it owns, which the page
  reading the chain writes into; and, where pages are served, the agents here
  in each fleet (`Regents.Keyfleet.Agents.Here`), read from the database once
  for every open page. `Regents.Application` starts it after PubSub and
  `Regents.SharedReading`, saying whether pages are served (`serving?`).
  Keyfleet's other processes come with the slice that starts them
  (`SOURCE.json`, `not_started`).
  """
  use Supervisor

  def start_link(serving?: serving?),
    do: Supervisor.start_link(__MODULE__, serving?, name: __MODULE__)

  @impl true
  def init(serving?) do
    Supervisor.init(
      [
        {Task.Supervisor, name: Regents.Keyfleet.ErrorSaves, max_children: 20},
        {Task.Supervisor, name: Regents.Keyfleet.PressBuilds},
        Regents.Keyfleet.AccessCache,
        Regents.Keyfleet.Chain.RewardsWaiting,
        if(serving?, do: Regents.Keyfleet.Agents.Here)
      ]
      |> Enum.reject(&is_nil/1),
      strategy: :one_for_one
    )
  end
end
