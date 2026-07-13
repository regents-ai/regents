defmodule Mix.Tasks.AshPlatform.ResetLocal do
  use Mix.Task

  @shortdoc "Removes one guarded disposable local acceptance database"

  @impl Mix.Task
  def run(args) do
    {options, [], []} = OptionParser.parse(args, strict: [run_id: :string])
    run_id = Keyword.fetch!(options, :run_id)
    adapter = Application.get_env(:ash_platform, :local_acceptance_database_adapter)

    opts = if adapter, do: [adapter: adapter], else: []
    AshPlatform.LocalDatabaseFixture.reset_local!(run_id, opts)
    File.rm_rf!("priv/static/assets")
    File.rm_rf!("priv/static/notebooks")
    File.rm("priv/static/cache_manifest.json")
    Mix.shell().info("Local acceptance database is absent for run #{run_id}.")
  end
end
