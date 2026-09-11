defmodule AshPlatform.LocalDatabaseFixture do
  @moduledoc false

  @acceptance_database_prefix "ash_platform_acceptance_"
  @protected_datasets ~w(
    platform_human_users
    basenames_mints
    basenames_mint_allowances
    basenames_payment_credits
  )
  @remote_environment_keys ~w(
    DATABASE_URL
    DATABASE_DIRECT_URL
    DATABASE_POOLED_URL
    FLY_APP_NAME
    FLY_REGION
  )

  def local_acceptance_config!(run_id) do
    username = System.fetch_env!("USER")

    config = [
      hostname: "127.0.0.1",
      port: 5432,
      database: @acceptance_database_prefix <> run_id,
      username: username,
      password: nil,
      pool_size: 2
    ]

    validate_acceptance_target!(:test, config, username)
    config
  end

  def preflight_toolchain! do
    unless :os.type() == {:unix, :darwin}, do: raise("local acceptance requires Darwin")
    validate_exact_output!("architecture", command_output!("uname", ["-m"]), "arm64")

    elixir_version =
      command_output!("elixir", ["--version"])
      |> extract_version!(~r/^Elixir (\d+\.\d+\.\d+) /m, "Elixir")

    validate_exact_output!("Elixir", elixir_version, "1.19.5")

    otp_version =
      command_output!("erl", [
        "-noshell",
        "-eval",
        "io:format(\"~s\", [erlang:system_info(otp_release)]), halt()."
      ])

    validate_exact_output!("Erlang/OTP", otp_version, "28")
    validate_exact_output!("Node", command_output!("node", ["--version"]), "v25.8.0")
    validate_exact_output!("npm", command_output!("npm", ["--version"]), "11.11.0")
    postgres_version = command_output!("psql", ["--version"])
    validate_postgres_version!(postgres_version)
    :ok
  end

  def validate_postgres_version!(output) when is_binary(output) do
    with [major, minor] <-
           Regex.run(
             ~r/\Apsql \(PostgreSQL\) (\d+)\.(\d+)(?:\.\d+)?(?:\s+[^\r\n]+)?\z/,
             String.trim(output),
             capture: :all_but_first
           ),
         {major, ""} <- Integer.parse(major),
         {minor, ""} <- Integer.parse(minor),
         true <- major > 14 or (major == 14 and minor >= 20) do
      :ok
    else
      false ->
        raise "local acceptance requires PostgreSQL 14.20 or newer"

      nil ->
        raise "local acceptance could not determine PostgreSQL version"

      _ ->
        raise "local acceptance could not determine PostgreSQL version"
    end
  end

  def setup_local!(run_id, opts \\ []) do
    config = Keyword.get_lazy(opts, :config, fn -> local_acceptance_config!(run_id) end)
    adapter = Keyword.get(opts, :adapter, __MODULE__.PostgresAdapter)
    env = Keyword.get_lazy(opts, :env, &current_env/0)
    expected_username = expected_username!(opts, env, adapter)

    reject_remote_environment!(Keyword.get_lazy(opts, :environment, &System.get_env/0))
    validate_acceptance_target!(env, config, expected_username)

    case adapter.create(config) do
      :ok ->
        try do
          adapter.prepare(config, run_id)
          :ok
        rescue
          error ->
            adapter.drop(config)
            reraise error, __STACKTRACE__
        end

      {:error, :already_up} ->
        raise "local acceptance fixture refused colliding run database"

      {:error, reason} ->
        raise "local acceptance database creation failed: #{inspect(reason)}"
    end
  end

  def reset_local!(run_id, opts \\ []) do
    config = Keyword.get_lazy(opts, :config, fn -> local_acceptance_config!(run_id) end)
    adapter = Keyword.get(opts, :adapter, __MODULE__.PostgresAdapter)
    env = Keyword.get_lazy(opts, :env, &current_env/0)
    expected_username = expected_username!(opts, env, adapter)

    reject_remote_environment!(Keyword.get_lazy(opts, :environment, &System.get_env/0))
    validate_acceptance_target!(env, config, expected_username)

    if adapter.exists?(config) do
      adapter.verify_owned!(config, run_id)

      case adapter.drop(config) do
        :ok -> :ok
        {:error, :already_down} -> :ok
        {:error, reason} -> raise "local acceptance database reset failed: #{inspect(reason)}"
      end
    else
      :ok
    end
  end

  def acceptance_database_exists!(run_id, opts \\ []) do
    config = Keyword.get_lazy(opts, :config, fn -> local_acceptance_config!(run_id) end)
    adapter = Keyword.get(opts, :adapter, __MODULE__.PostgresAdapter)
    env = Keyword.get_lazy(opts, :env, &current_env/0)
    expected_username = expected_username!(opts, env, adapter)
    environment = Keyword.get_lazy(opts, :environment, &System.get_env/0)

    reject_remote_environment!(environment)
    validate_acceptance_environment_run!(run_id, environment)
    validate_acceptance_target!(env, config, expected_username)
    validate_acceptance_run!(run_id, config)

    adapter.exists?(config)
  end

  def ensure_human_accounts!(opts \\ []) do
    repo = Keyword.get_lazy(opts, :repo, fn -> AshPlatform.Repo.config() end)
    env = Keyword.get_lazy(opts, :env, &current_env/0)
    environment = Keyword.get_lazy(opts, :environment, &System.get_env/0)

    validate_human_account_fixture_target!(env, repo, environment)

    setup = fixture_setup!(opts, env)
    setup.()
  end

  @doc false
  def validate_human_account_fixture_target!(env, repo, environment)
      when is_list(repo) and is_map(environment) do
    case environment["ASH_PLATFORM_ACCEPTANCE_RUN_ID"] do
      run_id when is_binary(run_id) and run_id != "" ->
        reject_remote_environment!(environment)
        expected_username = System.fetch_env!("USER")
        validate_acceptance_target!(env, repo, expected_username)

        if to_string(repo[:database]) == @acceptance_database_prefix <> run_id do
          :ok
        else
          raise "local acceptance fixture refused unsafe acceptance database target"
        end

      _ ->
        validate_target!(env, repo)
    end
  end

  defp setup_human_account_fixture! do
    create_local_human_accounts_table!()
    migrate_application_schema!()
    adopt_shared_schema_layout!()
  end

  defp fixture_setup!(opts, env) do
    case Keyword.fetch(opts, :setup) do
      {:ok, setup} when env == :test and is_function(setup, 0) -> setup
      :error -> &setup_human_account_fixture!/0
      _ -> raise "local human-account fixture refused injected setup"
    end
  end

  def validate_target!(env, repo) when is_list(repo) do
    host = to_string(repo[:hostname])
    database = to_string(repo[:database])

    if env in [:dev, :test] and host in ["127.0.0.1", "::1"] and
         (String.ends_with?(database, "_dev") or String.ends_with?(database, "_test")) do
      :ok
    else
      raise "local human-account fixture refused unsafe database target"
    end
  end

  def validate_acceptance_target!(env, repo, expected_username)
      when is_list(repo) and is_binary(expected_username) do
    host = to_string(repo[:hostname])
    database = to_string(repo[:database])
    username = to_string(repo[:username])

    run_id = String.replace_prefix(database, @acceptance_database_prefix, "")

    if safe_acceptance_target?(env, host, database, username, expected_username, run_id) do
      :ok
    else
      raise "local acceptance fixture refused unsafe acceptance database target"
    end
  end

  def reject_remote_environment!(environment) when is_map(environment) do
    present = Enum.filter(@remote_environment_keys, &nonempty?(environment[&1]))

    if present == [] do
      :ok
    else
      raise "local acceptance fixture refused remote environment configuration"
    end
  end

  def validate_ownership_marker!(rows, run_id, database, username) do
    if rows == [[run_id, database, username]] do
      :ok
    else
      raise "local acceptance database ownership marker mismatch"
    end
  end

  defp current_env do
    if Code.ensure_loaded?(Mix), do: Mix.env(), else: :prod
  end

  defp validate_acceptance_run!(run_id, config) do
    if to_string(config[:database]) == @acceptance_database_prefix <> run_id do
      :ok
    else
      raise "local acceptance fixture refused mismatched run database target"
    end
  end

  defp validate_acceptance_environment_run!(run_id, environment) do
    if environment["ASH_PLATFORM_ACCEPTANCE_RUN_ID"] == run_id do
      :ok
    else
      raise "local acceptance fixture requires exact run environment"
    end
  end

  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""

  defp expected_username!(opts, env, adapter) do
    case Keyword.fetch(opts, :expected_username) do
      {:ok, username}
      when env == :test and adapter != __MODULE__.PostgresAdapter and is_binary(username) and
             username != "" ->
        username

      :error ->
        System.fetch_env!("USER")

      _ ->
        raise "local acceptance fixture refused injected database role"
    end
  end

  # This private helper receives only fixed command names and fixed argument lists.
  # sobelow_skip ["CI.System"]
  defp command_output!(command, args) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {_output, _status} -> raise "local acceptance requires #{command}"
    end
  rescue
    ErlangError -> reraise "local acceptance requires #{command}", __STACKTRACE__
  end

  defp safe_acceptance_target?(env, host, database, username, expected_username, run_id) do
    env == :test and host == "127.0.0.1" and
      safe_acceptance_username?(username, expected_username) and
      safe_acceptance_database?(database) and safe_acceptance_run_id?(run_id)
  end

  defp safe_acceptance_username?(username, expected_username) do
    username == expected_username and expected_username != ""
  end

  defp safe_acceptance_database?(database) do
    database not in @protected_datasets and
      String.starts_with?(database, @acceptance_database_prefix) and byte_size(database) <= 63
  end

  defp safe_acceptance_run_id?(run_id) do
    run_id not in @protected_datasets and
      Regex.match?(~r/\A[a-z0-9](?:[a-z0-9_]*[a-z0-9])?\z/, run_id)
  end

  defp validate_exact_output!(name, actual, expected) do
    if actual == expected, do: :ok, else: raise("local acceptance requires #{name} #{expected}")
  end

  defp extract_version!(output, pattern, name) do
    case Regex.run(pattern, output, capture: :all_but_first) do
      [version] -> version
      _ -> raise "local acceptance could not determine #{name} version"
    end
  end

  defp migrate_application_schema! do
    migrations_path = Application.app_dir(:ash_platform, "priv/repo/migrations")
    Ecto.Migrator.run(AshPlatform.Repo, migrations_path, :up, all: true)
  end

  # A replayed migration history still writes the Autolaunch-owned tables to
  # their former `autolaunch` schema and the account table to `platform`; on the
  # shared database those live at `autolaunch_app` and `regent_names`, so the
  # replayed database adopts the same layout. Foreign keys follow the moved
  # account table because they reference it by identity, not by schema name.
  @doc false
  def adopt_shared_schema_layout! do
    Ecto.Adapters.SQL.query!(AshPlatform.Repo, "CREATE SCHEMA IF NOT EXISTS regent_names", [])

    Ecto.Adapters.SQL.query!(
      AshPlatform.Repo,
      """
      DO $$
      BEGIN
        IF to_regclass('platform.platform_human_users') IS NOT NULL
           AND to_regclass('regent_names.platform_human_users') IS NULL THEN
          ALTER TABLE platform.platform_human_users SET SCHEMA regent_names;
        END IF;
      END
      $$;
      """,
      []
    )

    Ecto.Adapters.SQL.query!(AshPlatform.Repo, "DROP SCHEMA IF EXISTS platform", [])

    Ecto.Adapters.SQL.query!(
      AshPlatform.Repo,
      """
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'autolaunch')
           AND NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'autolaunch_app') THEN
          ALTER SCHEMA autolaunch RENAME TO autolaunch_app;
        END IF;
      END
      $$;
      """,
      []
    )
  end

  # The migration history still references the account table at
  # `platform.platform_human_users`, so a database that has not yet adopted the
  # shared layout gets the table there for the replay to resolve against. A
  # database that already has the canonical `regent_names` copy needs nothing.
  @doc false
  def create_local_human_accounts_table! do
    Ecto.Adapters.SQL.query!(
      AshPlatform.Repo,
      """
      DO $$
      BEGIN
        IF to_regclass('regent_names.platform_human_users') IS NULL THEN
          CREATE SCHEMA IF NOT EXISTS platform;
          CREATE TABLE IF NOT EXISTS platform.platform_human_users (
            id bigserial PRIMARY KEY,
            privy_user_id varchar(255) NOT NULL UNIQUE,
            wallet_address varchar(255),
            wallet_addresses varchar(255)[] NOT NULL DEFAULT '{}',
            world_human_id varchar(255) UNIQUE,
            world_verified_at timestamp(0) without time zone,
            display_name varchar(80),
            avatar jsonb,
            created_at timestamp(0) without time zone NOT NULL,
            updated_at timestamp(0) without time zone NOT NULL
          );
        END IF;
      END
      $$;
      """,
      []
    )
  end

  defmodule PostgresAdapter do
    @moduledoc false

    def create(config), do: Ecto.Adapters.Postgres.storage_up(config)
    def drop(config), do: Ecto.Adapters.Postgres.storage_down(config)

    def exists?(config) do
      case Ecto.Adapters.Postgres.storage_status(config) do
        :up -> true
        :down -> false
        {:error, reason} -> raise "local acceptance database status failed: #{inspect(reason)}"
        other -> raise "local acceptance database status failed: #{inspect(other)}"
      end
    end

    def prepare(config, run_id) do
      with_repo(config, fn ->
        AshPlatform.LocalDatabaseFixture.create_local_human_accounts_table!()
        migrations_path = Application.app_dir(:ash_platform, "priv/repo/migrations")
        Ecto.Migrator.run(AshPlatform.Repo, migrations_path, :up, all: true)

        Ecto.Adapters.SQL.query!(AshPlatform.Repo, "CREATE SCHEMA acceptance_harness", [])

        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "CREATE TABLE acceptance_harness.baseline (run_id text PRIMARY KEY, database_name text NOT NULL, database_owner text NOT NULL, migration_versions text[] NOT NULL, empty_counts jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now())",
          []
        )

        {versions, empty_counts} = capture_baseline!()

        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "INSERT INTO acceptance_harness.baseline (run_id, database_name, database_owner, migration_versions, empty_counts) VALUES ($1, current_database(), current_user, $2, $3::jsonb)",
          [run_id, versions, empty_counts]
        )
      end)
    end

    def verify_owned!(config, run_id) do
      with_repo(config, fn ->
        marker =
          Ecto.Adapters.SQL.query!(
            AshPlatform.Repo,
            "SELECT run_id, database_name, database_owner FROM acceptance_harness.baseline",
            []
          )

        AshPlatform.LocalDatabaseFixture.validate_ownership_marker!(
          marker.rows,
          run_id,
          to_string(config[:database]),
          to_string(config[:username])
        )

        protected_tables =
          Ecto.Adapters.SQL.query!(
            AshPlatform.Repo,
            "SELECT table_schema, table_name FROM information_schema.tables WHERE table_name = ANY($1)",
            [
              [
                "platform_human_users",
                "basenames_mints",
                "basenames_mint_allowances",
                "basenames_payment_credits"
              ]
            ]
          ).rows

        Enum.each(protected_tables, &verify_empty_protected_table!/1)
      end)
    end

    # Catalog-derived identifiers are escaped by quote_identifier/1 before interpolation.
    # sobelow_skip ["SQL.Query"]
    defp verify_empty_protected_table!([schema, table]) do
      count =
        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "SELECT count(*) FROM #{quote_identifier(schema)}.#{quote_identifier(table)}",
          []
        )

      unless count.rows == [[0]] do
        raise "local acceptance protected dataset mirror is not empty"
      end
    end

    defp quote_identifier(identifier) do
      ~s("#{String.replace(identifier, "\"", "\"\"")}")
    end

    defp capture_baseline! do
      versions =
        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "SELECT version::text FROM schema_migrations ORDER BY version",
          []
        ).rows
        |> List.flatten()

      counts =
        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "SELECT (SELECT count(*) FROM discussions.comments)",
          []
        ).rows
        |> List.first()

      unless counts == [0] do
        raise "local acceptance empty product baseline mismatch"
      end

      {versions, counts}
    end

    defp with_repo(config, fun) do
      previous = Application.get_env(:ash_platform, AshPlatform.Repo)
      Application.put_env(:ash_platform, AshPlatform.Repo, config)
      {:ok, _} = Application.ensure_all_started(:ecto_sql)
      {:ok, pid} = AshPlatform.Repo.start_link()

      try do
        fun.()
      after
        Supervisor.stop(pid)

        if previous,
          do: Application.put_env(:ash_platform, AshPlatform.Repo, previous),
          else: Application.delete_env(:ash_platform, AshPlatform.Repo)
      end
    end
  end
end
