defmodule AshPlatform.Release do
  @moduledoc false

  @app :ash_platform
  @deployment_role_variable "ASH_PLATFORM_DEPLOYMENT_ROLE"
  @staging_role "staging"
  @platform_schema "regent_names"
  @bootstrap_role_error "bootstrap-staging requires #{@deployment_role_variable} to be exactly staging"
  @missing_migration_table_error "no schema_migrations table: run bootstrap-staging first"

  def migration_config!(getenv \\ &System.get_env/1) do
    AshPlatform.DatabaseConfig.release_config!(getenv)
  end

  def migrate do
    load_app()
    Application.put_env(@app, AshPlatform.Repo, migration_config!())

    Ecto.Migrator.with_repo(AshPlatform.Repo, fn repo -> repo.migrate!(migrations_path()) end)
  end

  @doc """
  Prepares an empty staging database for the first deployment.

  Staging owns a disposable database, so it has no copy of the tables this
  repository reads but does not own: `regent_names.platform_human_users` and the
  `autolaunch_app` tables. This command creates staging-only approximations of
  them with the shape the local fixture already proves sufficient, then runs
  every migration into `regents_app`.

  It refuses any database that already carries migration state or the
  regent_names schema, and it repairs nothing: recovery from a half-finished
  bootstrap is to destroy and recreate the staging database.
  """
  def bootstrap_staging, do: bootstrap_staging_for_test([])

  @doc false
  # No deployed command reaches this: the launchers call the arity-zero entry
  # points above, and this variant exists only so the test suite can aim the
  # commands at a disposable database.
  def bootstrap_staging_for_test(opts) when is_list(opts) do
    getenv = Keyword.get(opts, :getenv, &System.get_env/1)

    # The role is read before anything opens a connection, so no configuration
    # mistake can point this command at a database outside staging.
    if getenv.(@deployment_role_variable) != @staging_role do
      raise @bootstrap_role_error
    end

    load_app()
    Application.put_env(@app, AshPlatform.Repo, configuration!(opts, getenv))
    path = migrations_directory(opts)

    Ecto.Migrator.with_repo(AshPlatform.Repo, fn repo ->
      refuse_existing_state!(repo)

      # The fixture is the only definition of these tables' shape in the
      # repository, and the whole test suite runs on it. Calling it keeps
      # staging identical to that proven shape instead of copying it.
      AshPlatform.LocalDatabaseFixture.create_shared_tables!()

      repo.migrate!(path)
    end)
  end

  @doc """
  Lists what a deployed database and the release disagree about.

  Prints every migration the release carries that the database has not applied
  under `pending:`, and every version the database has applied whose file the
  release does not carry under `applied-without-file:`. Prints `none` when both
  are empty. It applies nothing, creates nothing, and takes no migration lock.
  """
  def pending_migrations, do: pending_migrations_for_test([])

  @doc false
  # Arity zero above for the same reason as the bootstrap: the deployed command
  # can only ever read the database its own release configuration resolves.
  def pending_migrations_for_test(opts) when is_list(opts) do
    getenv = Keyword.get(opts, :getenv, &System.get_env/1)
    load_app()
    Application.put_env(@app, AshPlatform.Repo, configuration!(opts, getenv))
    path = migrations_directory(opts)

    {:ok, {pending, applied_without_file}, _started} =
      Ecto.Migrator.with_repo(AshPlatform.Repo, fn repo ->
        collect_disagreements(repo, path)
      end)

    report(pending, applied_without_file)
  end

  defp collect_disagreements(repo, path) do
    migrations = migration_status(repo, path)
    carried = carried_versions(path)

    {for({:down, version, _name} <- migrations, do: version),
     for({:up, version, _name} <- migrations, not MapSet.member?(carried, version), do: version)}
  end

  defp migration_status(repo, path) do
    case read_migration_status(repo, path) do
      {:ok, migrations} -> migrations
      :no_migration_table -> raise @missing_migration_table_error
    end
  end

  defp read_migration_status(repo, path) do
    {:ok,
     Ecto.Migrator.migrations(repo, [path],
       prefix: repo.default_prefix(),
       skip_table_creation: true,
       migration_lock: false
     )}
  rescue
    error in Postgrex.Error ->
      if undefined_migration_table?(error, migration_source(repo)) do
        :no_migration_table
      else
        reraise error, __STACKTRACE__
      end
  end

  defp undefined_migration_table?(
         %Postgrex.Error{postgres: %{code: :undefined_table, message: message}},
         source
       ),
       do: String.contains?(message, source)

  defp undefined_migration_table?(_error, _source), do: false

  # Ecto names an applied version with no file after a placeholder marker. The
  # set of versions the release actually carries answers the same question
  # without depending on that marker's text.
  defp carried_versions(path) do
    path
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      case file |> Path.basename() |> Integer.parse() do
        {version, "_" <> _name} -> [version]
        _unversioned -> []
      end
    end)
    |> MapSet.new()
  end

  defp report([], []), do: IO.puts("none")

  defp report(pending, applied_without_file) do
    if pending != [], do: IO.puts("pending: #{Enum.join(pending, " ")}")

    if applied_without_file != [] do
      IO.puts("applied-without-file: #{Enum.join(applied_without_file, " ")}")
    end
  end

  defp refuse_existing_state!(repo) do
    prefix = repo.default_prefix()
    source = migration_source(repo)

    if table_exists?(repo, prefix, source) do
      raise "#{prefix}.#{source} already exists: destroy and recreate the staging database"
    end

    if schema_exists?(repo, @platform_schema) do
      raise "#{@platform_schema} schema already exists: destroy and recreate the staging database"
    end
  end

  defp table_exists?(repo, prefix, table) do
    %{rows: [[exists?]]} =
      Ecto.Adapters.SQL.query!(
        repo,
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
          WHERE n.nspname = $1 AND c.relname = $2 AND c.relkind IN ('r', 'p')
        )
        """,
        [prefix, table]
      )

    exists?
  end

  defp schema_exists?(repo, schema) do
    %{rows: [[exists?]]} =
      Ecto.Adapters.SQL.query!(
        repo,
        "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = $1)",
        [schema]
      )

    exists?
  end

  defp migration_source(repo), do: repo.config()[:migration_source] || "schema_migrations"

  defp configuration!(opts, getenv) do
    Keyword.get_lazy(opts, :config, fn -> migration_config!(getenv) end)
  end

  defp migrations_directory(opts) do
    Keyword.get_lazy(opts, :migrations_path, &migrations_path/0)
  end

  defp load_app do
    case Application.load(@app) do
      :ok -> :ok
      {:error, {:already_loaded, @app}} -> :ok
    end
  end

  defp migrations_path do
    Application.app_dir(@app, "priv/repo/migrations")
  end
end
