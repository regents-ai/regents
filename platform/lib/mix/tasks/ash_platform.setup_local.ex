defmodule Mix.Tasks.AshPlatform.SetupLocal do
  use Mix.Task

  @shortdoc "Creates one guarded disposable local acceptance database"

  @impl Mix.Task
  def run(args) do
    {options, [], []} = OptionParser.parse(args, strict: [run_id: :string])
    run_id = Keyword.fetch!(options, :run_id)
    adapter = Application.get_env(:ash_platform, :local_acceptance_database_adapter)

    opts = if adapter, do: [adapter: adapter], else: []
    AshPlatform.LocalDatabaseFixture.preflight_toolchain!()
    AshPlatform.LocalDatabaseFixture.setup_local!(run_id, opts)

    try do
      if Application.get_env(:ash_platform, :local_acceptance_build_assets, true) do
        {_, 0} = System.cmd("npm", ["ci"], into: IO.stream(), stderr_to_stdout: true)
        Mix.Task.run("assets.build")
      end

      Mix.shell().info("Local acceptance database is ready for run #{run_id}.")
    rescue
      error ->
        AshPlatform.LocalDatabaseFixture.reset_local!(run_id, opts)
        reraise error, __STACKTRACE__
    end
  end
end
