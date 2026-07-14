defmodule Mix.Tasks.AshPlatform.SetupLocalAuth do
  use Mix.Task

  @shortdoc "Prepares the guarded local Ash Platform database"

  @impl true
  def run(_args) do
    unless Mix.env() in [:dev, :test], do: Mix.raise("local auth setup is dev/test only")
    Mix.Task.run("app.start")
    AshPlatform.LocalDatabaseFixture.ensure_human_accounts!()
    Mix.shell().info("Local Ash Platform database is ready.")
  end
end
