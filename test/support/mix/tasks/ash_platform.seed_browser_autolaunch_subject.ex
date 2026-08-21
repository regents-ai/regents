defmodule Mix.Tasks.AshPlatform.SeedBrowserAutolaunchSubject do
  use Mix.Task

  @shortdoc "Seeds, or removes, the deterministic subject the browser wallet proof acts on"

  @moduledoc """
  Seeds one subject whose addresses are exactly the ones the deterministic
  subject-wallet chain client answers about.

  The browser proof and `mix test` share one local test database, and a public
  subject that outlived a browser run would change what the ordinary suite sees
  listed. So this subject exists only for the life of the browser server: the
  seed removes any earlier one before creating its own, and `--remove` takes it
  away again when that server stops.

  Nothing here is reviewed evidence: the addresses are fixture values, and the
  client that answers about them never contacts a provider.
  """

  @subject_id "subject:browser:wallet"

  @impl true
  def run(args) do
    env = Mix.env()
    repo_config = AshPlatform.Repo.config()
    validate_target!(env, repo_config)

    Mix.Task.run("app.start")

    if "--remove" in args, do: remove!(), else: seed!()
  end

  @doc "The subject identity the browser proof visits."
  @spec subject_id() :: String.t()
  def subject_id, do: @subject_id

  @doc "Replaces any earlier browser subject with a fresh one."
  @spec seed!() :: :ok
  def seed! do
    remove!()
    AshPlatform.SubjectWalletFixture.subject!(@subject_id)
    :ok
  end

  @doc "Takes the browser subject, and anything it owns, back out of the shared database."
  @spec remove!() :: :ok
  def remove! do
    # The operation table keys a subject by its public identity; the action table
    # keys it by the subject row's own id, so that one is removed through it.
    delete!("DELETE FROM autolaunch.subject_wallet_operations WHERE subject_id = $1")

    delete!("""
    DELETE FROM autolaunch.subject_actions
     WHERE subject_id IN (SELECT id FROM autolaunch.subjects WHERE subject_id = $1)
    """)

    delete!("DELETE FROM autolaunch.subjects WHERE subject_id = $1")
    :ok
  end

  @doc "Refuses any database that is not a local test database."
  def validate_target!(env, repo_config) when is_list(repo_config) do
    AshPlatform.LocalDatabaseFixture.validate_target!(env, repo_config)
    database = to_string(repo_config[:database])

    if env == :test and String.ends_with?(database, "_test") do
      :ok
    else
      raise "browser Autolaunch subject seed refused unsafe database target"
    end
  end

  # Scoped to this one fixture identity by parameter, never by interpolation.
  defp delete!(sql), do: Ecto.Adapters.SQL.query!(AshPlatform.Repo, sql, [@subject_id])
end
