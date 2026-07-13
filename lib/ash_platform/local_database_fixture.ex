defmodule AshPlatform.LocalDatabaseFixture do
  @moduledoc false

  @acceptance_database_prefix "ash_platform_acceptance_"
  @protected_datasets ~w(
    platform_human_users
    basenames_mints
    basenames_mint_allowances
    basenames_payment_credits
  )
  @remote_environment_keys ~w(DATABASE_URL DATABASE_DIRECT_URL FLY_APP_NAME FLY_REGION)

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
    require_command!("uname", ["-m"], "arm64")
    require_command!("elixir", ["--version"], "Elixir 1.19.5")

    require_command!(
      "erl",
      ["-noshell", "-eval", "io:format(\"~s\", [erlang:system_info(otp_release)]), halt()."],
      "28"
    )

    require_command!("node", ["--version"], "v25.8.0")
    require_command!("npm", ["--version"], "11.11.0")
    {postgres_version, 0} = System.cmd("psql", ["--version"], stderr_to_stdout: true)
    validate_postgres_version!(postgres_version)
    :ok
  end

  def validate_postgres_version!(output) when is_binary(output) do
    with [version] <- Regex.run(~r/\b(\d+\.\d+)(?:\.\d+)?\b/, output, capture: :all_but_first),
         {:ok, parsed} <- Version.parse(version <> ".0"),
         :lt <- Version.compare(parsed, Version.parse!("14.20.0")) do
      raise "local acceptance requires PostgreSQL 14.20 or newer"
    else
      [_, _ | _] -> raise "local acceptance could not determine PostgreSQL version"
      nil -> raise "local acceptance could not determine PostgreSQL version"
      {:error, _} -> raise "local acceptance could not determine PostgreSQL version"
      _comparison -> :ok
    end
  end

  def setup_local!(run_id, opts \\ []) do
    config = Keyword.get_lazy(opts, :config, fn -> local_acceptance_config!(run_id) end)
    expected_username = Keyword.fetch!(config, :username) |> to_string()
    adapter = Keyword.get(opts, :adapter, __MODULE__.PostgresAdapter)
    env = Keyword.get_lazy(opts, :env, &current_env/0)

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
    expected_username = Keyword.fetch!(config, :username) |> to_string()
    adapter = Keyword.get(opts, :adapter, __MODULE__.PostgresAdapter)
    env = Keyword.get_lazy(opts, :env, &current_env/0)

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

  def ensure_human_accounts! do
    repo = AshPlatform.Repo.config()
    validate_target!(current_env(), repo)
    create_local_human_accounts_table!()
    migrate_application_schema!()
    seed_techtree!()
  end

  def validate_target!(env, repo) when is_list(repo) do
    host = to_string(repo[:hostname])
    database = to_string(repo[:database])

    if env in [:dev, :test] and host in ["127.0.0.1", "localhost", "::1"] and
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

    safe? =
      env == :test and host == "127.0.0.1" and username == expected_username and
        expected_username != "" and database not in @protected_datasets and
        String.starts_with?(database, @acceptance_database_prefix) and byte_size(database) <= 63 and
        Regex.match?(~r/\A[a-z0-9](?:[a-z0-9_]*[a-z0-9])?\z/, run_id)

    if safe? do
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

  defp current_env do
    if Code.ensure_loaded?(Mix), do: Mix.env(), else: :prod
  end

  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""

  defp require_command!(command, args, expected) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} ->
        unless String.contains?(output, expected) do
          raise "local acceptance requires #{command} #{expected}"
        end

      {_output, _status} ->
        raise "local acceptance requires #{command} #{expected}"
    end
  rescue
    ErlangError -> raise "local acceptance requires #{command} #{expected}"
  end

  defp migrate_application_schema! do
    migrations_path = Path.expand("../../priv/repo/migrations", __DIR__)
    Ecto.Migrator.run(AshPlatform.Repo, migrations_path, :up, all: true)
  end

  @doc false
  def create_local_human_accounts_table! do
    Ecto.Adapters.SQL.query!(AshPlatform.Repo, "CREATE SCHEMA IF NOT EXISTS platform", [])

    Ecto.Adapters.SQL.query!(
      AshPlatform.Repo,
      """
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
      )
      """,
      []
    )
  end

  defp seed_techtree! do
    case AshPlatform.Techtree.ensure_seed_trees(actor: %AshPlatform.Actors.System{}) do
      :ok -> :ok
      {:error, error} -> raise error
    end
  end

  defmodule PostgresAdapter do
    @moduledoc false

    def create(config), do: Ecto.Adapters.Postgres.storage_up(config)
    def drop(config), do: Ecto.Adapters.Postgres.storage_down(config)

    def exists?(config) do
      Ecto.Adapters.Postgres.storage_status(config) == :up
    end

    def prepare(config, run_id) do
      with_repo(config, fn ->
        AshPlatform.LocalDatabaseFixture.create_local_human_accounts_table!()
        migrations_path = Path.expand("../../priv/repo/migrations", __DIR__)
        Ecto.Migrator.run(AshPlatform.Repo, migrations_path, :up, all: true)

        case AshPlatform.Techtree.ensure_seed_trees(actor: %AshPlatform.Actors.System{}) do
          :ok -> :ok
          {:error, error} -> raise error
        end

        Ecto.Adapters.SQL.query!(AshPlatform.Repo, "CREATE SCHEMA acceptance_harness", [])

        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "CREATE TABLE acceptance_harness.baseline (run_id text PRIMARY KEY, migration_versions text[] NOT NULL, seed_count bigint NOT NULL, seed_fingerprint text NOT NULL, empty_counts jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now())",
          []
        )

        {versions, seed_count, seed_fingerprint, empty_counts} = capture_baseline!()

        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "INSERT INTO acceptance_harness.baseline (run_id, migration_versions, seed_count, seed_fingerprint, empty_counts) VALUES ($1, $2, $3, $4, $5::jsonb)",
          [run_id, versions, seed_count, seed_fingerprint, empty_counts]
        )
      end)
    end

    def verify_owned!(config, run_id) do
      with_repo(config, fn ->
        stored =
          Ecto.Adapters.SQL.query!(
            AshPlatform.Repo,
            "SELECT run_id, migration_versions, seed_count, seed_fingerprint, empty_counts FROM acceptance_harness.baseline",
            []
          )

        current = capture_baseline!()

        unless stored.rows == [[run_id | Tuple.to_list(current)]] do
          raise "local acceptance database ownership marker mismatch"
        end

        protected_humans =
          Ecto.Adapters.SQL.query!(
            AshPlatform.Repo,
            "SELECT count(*) FROM platform.platform_human_users",
            []
          )

        other_protected =
          Ecto.Adapters.SQL.query!(
            AshPlatform.Repo,
            "SELECT table_name FROM information_schema.tables WHERE table_name = ANY($1)",
            [["basenames_mints", "basenames_mint_allowances", "basenames_payment_credits"]]
          )

        unless protected_humans.rows == [[0]] and other_protected.rows == [] do
          raise "local acceptance protected dataset mirror is not empty"
        end
      end)
    end

    defp capture_baseline! do
      versions =
        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "SELECT version::text FROM schema_migrations ORDER BY version",
          []
        ).rows
        |> List.flatten()

      seed_rows =
        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "SELECT slug, name, description, position FROM techtree.trees ORDER BY position, slug",
          []
        ).rows

      expected_seed_rows =
        Enum.map(AshPlatform.Techtree.SeedTrees.all(), fn tree ->
          [tree.slug, tree.name, tree.description, tree.position]
        end)

      unless seed_rows == expected_seed_rows do
        raise "local acceptance reference seed baseline mismatch"
      end

      seed_fingerprint =
        seed_rows
        |> :erlang.term_to_binary()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      counts =
        Ecto.Adapters.SQL.query!(
          AshPlatform.Repo,
          "SELECT (SELECT count(*) FROM techtree.nodes), (SELECT count(*) FROM techtree.notebook_artifacts), (SELECT count(*) FROM discussions.comments), (SELECT count(*) FROM discussions.comment_reactions)",
          []
        ).rows
        |> List.first()

      unless counts == [0, 0, 0, 0] do
        raise "local acceptance empty product baseline mismatch"
      end

      {versions, length(seed_rows), seed_fingerprint, counts}
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
