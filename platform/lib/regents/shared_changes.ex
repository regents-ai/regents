defmodule Regents.SharedChanges do
  @moduledoc """
  Changes made on any Regent site reach this site's open pages: a Credits balance
  (`RegentCredits.Listener`), a pairing made or ended (`RegentAgents.Listener`)
  and refreshed staking figures (`Regents.Staking.SnapshotListener`) arrive as
  database notices. All three listen on one connection of the site's own,
  `Regents.Notifications` (`Regents.DatabaseConfig.notifications_config/1`). The
  connection starts first, so a new connection brings new listeners.
  """

  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    connection = Regents.DatabaseConfig.notifications_config(Regents.Repo.config())

    children = [
      {Postgrex.Notifications, [name: Regents.Notifications] ++ connection},
      RegentCredits.Listener,
      RegentAgents.Listener,
      Regents.Staking.SnapshotListener
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
