defmodule Mix.Tasks.Regents.SetupLocalAuth do
  use Mix.Task

  @shortdoc "Prepares the guarded local Regents database"

  @impl true
  def run(_args) do
    unless Mix.env() in [:dev, :test], do: Mix.raise("local auth setup is dev/test only")
    # Only the repo runs: the site's Oban refuses to start until these tables exist.
    Mix.Task.run("app.config")

    {:ok, _result, _apps} =
      Ecto.Migrator.with_repo(Regents.Repo, fn _repo ->
        Regents.LocalDatabaseFixture.ensure_human_accounts!()
      end)

    Mix.shell().info("Local Regents database is ready.")
  end
end
