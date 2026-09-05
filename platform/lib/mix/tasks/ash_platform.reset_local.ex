defmodule Mix.Tasks.AshPlatform.ResetLocal do
  use Mix.Task

  @shortdoc "Removes one guarded disposable local acceptance database"
  @run_reset_injection_keys [
    :database_exists,
    :start_application,
    :preflight,
    :identity_cleanup,
    :database_reset,
    :stop_application,
    :cleanup_files
  ]
  @reset_injection_keys [
    :preflight,
    :identity_cleanup,
    :database_reset,
    :stop_application,
    :cleanup_files?
  ]

  @impl Mix.Task
  def run(args) do
    {options, [], []} = OptionParser.parse(args, strict: [run_id: :string])
    run_id = Keyword.fetch!(options, :run_id)
    run_reset!(run_id)
  end

  @doc false
  def run_reset!(run_id, opts \\ []) do
    reject_injected_options!(opts, @run_reset_injection_keys, "orchestration")
    adapter = Application.get_env(:ash_platform, :local_acceptance_database_adapter)
    database_opts = if adapter, do: [adapter: adapter], else: []

    database_exists =
      Keyword.get(
        opts,
        :database_exists,
        &AshPlatform.LocalDatabaseFixture.acceptance_database_exists!/2
      )

    cleanup_files = Keyword.get(opts, :cleanup_files, &cleanup_generated_files!/0)

    if database_exists.(run_id, database_opts) do
      start_application = Keyword.get(opts, :start_application, &start_application!/0)
      start_application.()

      reset_opts =
        opts
        |> Keyword.put_new(:stop_application, fn -> Application.stop(:ash_platform) end)
        |> Keyword.put(:cleanup_files?, false)

      perform_reset!(run_id, reset_opts)
      cleanup_files.()
    else
      cleanup_files.()
      report_absent(run_id)
    end
  end

  @doc false
  def reset!(run_id, opts \\ []) do
    reject_injected_options!(opts, @reset_injection_keys, "cleanup")
    perform_reset!(run_id, opts)
  end

  defp perform_reset!(run_id, opts) do
    adapter = Application.get_env(:ash_platform, :local_acceptance_database_adapter)

    preflight =
      Keyword.get(opts, :preflight, &Mix.Tasks.AshPlatform.ResetBrowserIdentity.preflight!/1)

    identity_cleanup =
      Keyword.get(opts, :identity_cleanup, &Mix.Tasks.AshPlatform.ResetBrowserIdentity.reset!/1)

    database_reset =
      Keyword.get(opts, :database_reset, &AshPlatform.LocalDatabaseFixture.reset_local!/2)

    stop_application = Keyword.get(opts, :stop_application, fn -> :ok end)

    proof = preflight.(run_id)
    identity_cleanup.(preflight: proof)
    stop_application.()

    database_opts = if adapter, do: [adapter: adapter], else: []
    database_reset.(run_id, database_opts)

    if Keyword.get(opts, :cleanup_files?, true), do: cleanup_generated_files!()

    report_absent(run_id)
  end

  defp reject_injected_options!(opts, keys, label) do
    injected? = Enum.any?(keys, &Keyword.has_key?(opts, &1))

    if injected? and Mix.env() != :test do
      raise "local acceptance reset refused injected #{label}"
    end
  end

  defp start_application! do
    Mix.Task.run("app.start")
    :ok
  end

  defp cleanup_generated_files! do
    File.rm_rf!("priv/static/assets")
    File.rm("priv/static/cache_manifest.json")
    :ok
  end

  defp report_absent(run_id) do
    Mix.shell().info("Local acceptance database is absent for run #{run_id}.")
    :ok
  end
end
