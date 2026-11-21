defmodule Regents do
  @moduledoc """
  Regents keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  use Boundary,
    deps: [Regents.Chain],
    exports: [
      Alert,
      Blog,
      Blog.PostFile,
      DatabaseConfig,
      Health,
      Legal,
      Limits,
      Messages,
      Messages.Message,
      Messages.Refused,
      OpenSea,
      OpenSea.HoldingsCache,
      PaperProDaily,
      PaperProDaily.PaperFile,
      PaperProDaily.Publication,
      RateLimiter,
      Repo,
      SharedReading,
      SiteTools,
      Updates,
      Account,
      Account.AccessContext,
      Account.AccessContext.AccountControl,
      Account.Accounts,
      Account.Accounts.HumanAccount,
      Account.Accounts.LinkedIdentity.Providers,
      Account.Accounts.SessionAuthority,
      Account.Accounts.VerifiedSession,
      Account.Actors.Admin,
      Account.Actors.Agent,
      Account.Actors.ConnectedApp,
      Account.Actors.Human,
      Account.Actors.System,
      Account.AgentPicture,
      Account.Agents,
      Account.Agents.ActivityReading,
      Account.Ens,
      Account.Formation,
      Account.Names,
      Account.Names.Snapshot,
      Account.Points.Board,
      Account.PublicIdentity
    ]

  @doc """
  Whether the signed-in account, or the admin actor acting for it, is one of the
  site's admins (`config :regents, :admins`).
  """
  def admin?(%{privy_user_id: id}), do: id in Application.fetch_env!(:regents, :admins)
  def admin?(_nobody), do: false

  @doc """
  Whether this site only reads its database: the read-only venue, the `reader`
  role (`Regents.DatabaseConfig`), whose login the database holds to reading a
  short list of tables. There the site starts no background work and no Points
  board, nobody signs in (no sign-in is read), and every request that signs in,
  pairs, checks in or saves is refused plainly (`RegentsWeb.Plugs.ReadOnly`).
  """
  def read_only?, do: Application.fetch_env!(:regents, :read_only)
end
