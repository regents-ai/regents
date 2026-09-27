defmodule Mix.Tasks.Regents.SetupLocalAuth do
  use Mix.Task

  @shortdoc "Prepares the guarded local Regents database"

  @impl true
  def run(_args) do
    unless Mix.env() in [:dev, :test], do: Mix.raise("local auth setup is dev/test only")
    Mix.Task.run("app.start")
    Regents.LocalDatabaseFixture.ensure_human_accounts!()
    Mix.shell().info("Local Regents database is ready.")
  end
end
