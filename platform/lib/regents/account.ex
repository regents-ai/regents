defmodule Regents.Account do
  @moduledoc """
  Account: sign-in and sessions, actors, names, points, Regent profiles, agents and
  pairing, ENS and public identity.
  """
  use Boundary,
    deps: [Regents],
    exports: [
      AccessContext,
      AccessContext.AccountControl,
      Accounts,
      Accounts.HumanAccount,
      Accounts.LinkedIdentity.Providers,
      Accounts.PublicLink,
      Accounts.SessionAuthority,
      Accounts.VerifiedSession,
      Actors.Admin,
      Actors.Agent,
      Actors.ConnectedApp,
      Actors.Human,
      Actors.System,
      AgentPicture,
      Agents,
      Agents.ActivityReading,
      Agents.Connection,
      Agents.Connection.Refused,
      Agents.HostedAddress,
      Agents.PairedPersonWallet,
      Ens,
      Formation,
      Names,
      Names.Snapshot,
      Points.Board,
      PublicIdentity
    ]

  @doc "`:ok` when the site's database answers (`Regents.Products.health/0`)."
  def health do
    if Regents.Health.database_ready?(), do: :ok, else: {:error, :database_unavailable}
  end
end
