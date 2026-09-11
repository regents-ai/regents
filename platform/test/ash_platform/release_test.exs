defmodule AshPlatform.ReleaseTest do
  # The bootstrap and listing cases point the application repository at a
  # disposable database, so this module runs alone.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshPlatform.LocalDatabaseFixture
  alias AshPlatform.LocalDatabaseFixture.PostgresAdapter
  alias AshPlatform.Release

  @moduletag timeout: 300_000

  @direct "postgresql://direct_user:direct-secret@direct.dzx6qo6xqzvojpv5.flympg.net:5432/ash_platform"
  @role "ASH_PLATFORM_DEPLOYMENT_ROLE"
  @role_error "bootstrap-staging requires ASH_PLATFORM_DEPLOYMENT_ROLE to be exactly staging"
  @missing_table_error "no schema_migrations table: run bootstrap-staging first"
  @unreachable [
    hostname: "127.0.0.1",
    port: 1,
    database: "ash_platform_refused",
    username: "nobody",
    password: nil,
    pool_size: 1
  ]
  @migrate_launcher """
  #!/bin/sh
  set -eu

  ASH_PLATFORM_RELEASE_COMMAND=migrate exec "$(dirname "$0")/ash_platform" eval 'AshPlatform.Release.migrate()'
  """

  # Two cases migrate a database from scratch inside one VM, so the same
  # migration modules are loaded more than once. That redefinition is expected
  # here and nothing else compiles while this module runs.
  setup do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)
    on_exit(fn -> Code.put_compiler_option(:ignore_module_conflict, previous) end)
    :ok
  end

  test "migration configuration uses only direct access" do
    getenv = fn
      "DATABASE_DIRECT_URL" -> @direct
      "ASH_PLATFORM_DEPLOYMENT_ROLE" -> "production"
      "ASH_PLATFORM_DATABASE_TARGET_MODE" -> "production"
      "ASH_PLATFORM_DATABASE_CLUSTER_ID" -> "dzx6qo6xqzvojpv5"
      "ASH_PLATFORM_DATABASE_CLUSTER_NAME" -> "regents-platform-prod"
      "DATABASE_POOLED_URL" -> flunk("migration configuration read pooled access")
      _name -> nil
    end

    assert Release.migration_config!(getenv) == [
             ssl: [
               verify: :verify_peer,
               cacerts: :public_key.cacerts_get(),
               server_name_indication: ~c"direct.dzx6qo6xqzvojpv5.flympg.net",
               customize_hostname_check: [
                 match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
               ]
             ],
             port: 5432,
             url: @direct,
             socket_options: [:inet6]
           ]
  end

  test "migration configuration fails closed without an explicit production target" do
    assert_raise RuntimeError,
                 "database migration requires production mode for cluster dzx6qo6xqzvojpv5 named regents-platform-prod",
                 fn ->
                   Release.migration_config!(fn
                     @role -> "production"
                     _name -> nil
                   end)
                 end
  end

  test "PKG-MIGRATION launcher invokes the guarded release migration without printing variables" do
    script = File.read!("rel/overlays/bin/migrate")

    assert script == @migrate_launcher
    assert script =~ "AshPlatform.Release.migrate()"
    assert script =~ "ASH_PLATFORM_RELEASE_COMMAND=migrate"
    refute script =~ "ASH_PLATFORM_DATABASE_TARGET_MODE="
    refute script =~ "bootstrap"
    refute script =~ "echo"
    refute script =~ "DATABASE_POOLED_URL"
    refute script =~ "DATABASE_DIRECT_URL"
  end

  test "the staging launchers invoke the guarded functions without printing variables" do
    exports = Release.__info__(:functions)

    for {path, command} <- [
          {"rel/overlays/bin/bootstrap-staging", :bootstrap_staging},
          {"rel/overlays/bin/pending-migrations", :pending_migrations}
        ] do
      script = File.read!(path)

      assert script =~ "AshPlatform.Release.#{command}()"
      assert script =~ "ASH_PLATFORM_RELEASE_COMMAND=migrate"
      refute script =~ "ASH_PLATFORM_DEPLOYMENT_ROLE="
      refute script =~ "echo"
      refute script =~ "DATABASE_POOLED_URL"
      refute script =~ "DATABASE_DIRECT_URL"
      refute script =~ "_for_test"
      assert File.stat!(path).mode |> Bitwise.band(0o100) != 0

      # Every deployed command takes no arguments, so nothing a deployment can
      # write on the command line chooses which database the release touches.
      assert {command, 0} in exports
      refute {command, 1} in exports
    end
  end

  test "bootstrap refuses every role but staging before it opens a connection" do
    for role <- [nil, "", "production", "Staging", "staging ", "rehearsal"] do
      getenv = fn
        @role -> role
        name -> flunk("bootstrap read #{name} before it checked the deployment role")
      end

      assert_raise RuntimeError, @role_error, fn ->
        Release.bootstrap_staging_for_test(getenv: getenv, config: @unreachable)
      end
    end
  end

  test "bootstrap refuses a database that already carries migration state" do
    config = disposable_database()

    assert {:ok, _result, _started} =
             Release.bootstrap_staging_for_test(
               getenv: staging_getenv(),
               config: config,
               migrations_path: migrations_directory([])
             )

    assert_raise RuntimeError,
                 "regents_app.schema_migrations already exists: destroy and recreate the staging database",
                 fn ->
                   Release.bootstrap_staging_for_test(getenv: staging_getenv(), config: config)
                 end
  end

  test "bootstrap refuses a database that already has the regent_names schema, and changes nothing" do
    config = disposable_database()
    query!(config, "CREATE SCHEMA regent_names")

    assert_raise RuntimeError,
                 "regent_names schema already exists: destroy and recreate the staging database",
                 fn ->
                   Release.bootstrap_staging_for_test(getenv: staging_getenv(), config: config)
                 end

    refute migration_table?(config)
  end

  test "bootstrap prepares an empty staging database and runs every migration to completion" do
    config = disposable_database()

    assert {:ok, _result, _started} =
             Release.bootstrap_staging_for_test(getenv: staging_getenv(), config: config)

    assert column_names(config, "regent_names", "platform_human_users") == [
             "avatar",
             "created_at",
             "display_name",
             "id",
             "privy_user_id",
             "updated_at",
             "wallet_address",
             "wallet_addresses",
             "world_human_id",
             "world_verified_at"
           ]

    assert applied_versions(config) == release_versions()

    assert table_names(config, "regents_app") == [
             "account_ens_identities",
             "agent_links",
             "agent_pairing_codes",
             "cloud_runtimes",
             "comments",
             "linked_identities",
             "regents",
             "schema_migrations",
             "session_authorities"
           ]

    assert "launch_drafts" in table_names(config, "autolaunch_app")
  end

  test "the listing prints none on a database the release agrees with" do
    config = bootstrapped_database()

    assert capture_io(fn -> Release.pending_migrations_for_test(config: config) end) == "none\n"
  end

  test "the listing names every version the release carries that the database has not applied" do
    config = disposable_database()
    held_back = release_migration_files() |> Enum.take(-2)

    assert {:ok, _result, _started} =
             Release.bootstrap_staging_for_test(
               getenv: staging_getenv(),
               config: config,
               migrations_path: migrations_directory(release_migration_files() -- held_back)
             )

    expected = Enum.map_join(held_back, " ", &version_of/1)

    assert capture_io(fn -> Release.pending_migrations_for_test(config: config) end) ==
             "pending: #{expected}\n"
  end

  test "the listing names every applied version whose file the release does not carry" do
    config = bootstrapped_database()

    query!(
      config,
      "INSERT INTO regents_app.schema_migrations (version, inserted_at) VALUES ($1, NOW()::timestamp)",
      [20_990_101_000_000]
    )

    assert capture_io(fn -> Release.pending_migrations_for_test(config: config) end) ==
             "applied-without-file: 20990101000000\n"
  end

  test "the listing refuses a database with no migration table and creates nothing" do
    config = disposable_database()

    assert_raise RuntimeError, @missing_table_error, fn ->
      Release.pending_migrations_for_test(config: config)
    end

    refute migration_table?(config)
  end

  # The listing is meant to be safe to run while a migration is in flight, which
  # is only true if it never queues behind the migration lock. A second
  # connection holds exactly the lock Ecto's Postgres adapter takes for
  # migrations, and both reads run against the same configuration: the listing
  # completes, and the otherwise identical read that does take the lock waits
  # for it until the connection's lock timeout cancels it.
  test "the listing reads a database whose migration lock is held, unlike a read that takes it" do
    config = with_lock_timeout(bootstrapped_database())
    hold_migration_lock(config)

    assert capture_io(fn -> Release.pending_migrations_for_test(config: config) end) == "none\n"

    # Ecto's migrator matches on a successful lock statement, so the cancelled
    # wait reaches the caller as a MatchError carrying PostgreSQL's own reason.
    error = assert_raise MatchError, fn -> locking_migration_status(config) end
    assert {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} = error.term
  end

  defp staging_getenv do
    fn
      @role -> "staging"
      _name -> nil
    end
  end

  # The application repository is running against the shared test database, so
  # every case that points the release commands somewhere else takes it down
  # first and puts it back exactly as it was.
  defp disposable_database do
    run_id = "regent2e7_#{System.unique_integer([:positive])}"
    config = LocalDatabaseFixture.local_acceptance_config!(run_id)
    previous = Application.get_env(:ash_platform, AshPlatform.Repo)

    :ok = Supervisor.terminate_child(AshPlatform.Supervisor, AshPlatform.Repo)
    :ok = PostgresAdapter.create(config)

    on_exit(fn ->
      PostgresAdapter.drop(config)
      Application.put_env(:ash_platform, AshPlatform.Repo, previous)
      {:ok, _pid} = Supervisor.restart_child(AshPlatform.Supervisor, AshPlatform.Repo)
      Ecto.Adapters.SQL.Sandbox.mode(AshPlatform.Repo, :manual)
    end)

    config
  end

  defp bootstrapped_database do
    config = disposable_database()

    assert {:ok, _result, _started} =
             Release.bootstrap_staging_for_test(getenv: staging_getenv(), config: config)

    config
  end

  defp migrations_directory(files) do
    directory =
      Path.join(System.tmp_dir!(), "regent-2e7-migrations-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    Enum.each(files, fn file ->
      File.cp!(Path.join(release_migrations_path(), file), Path.join(directory, file))
    end)

    directory
  end

  defp release_migrations_path,
    do: Application.app_dir(:ash_platform, "priv/repo/migrations")

  defp release_migration_files do
    release_migrations_path()
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp release_versions, do: Enum.map(release_migration_files(), &version_of/1)

  defp version_of(file) do
    {version, "_" <> _name} = Integer.parse(file)
    version
  end

  defp applied_versions(config) do
    config
    |> query!("SELECT version FROM regents_app.schema_migrations ORDER BY version")
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  defp column_names(config, schema, table) do
    config
    |> query!(
      "SELECT column_name FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2 ORDER BY column_name",
      [schema, table]
    )
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  defp table_names(config, schema) do
    config
    |> query!(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY table_name",
      [schema]
    )
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  defp migration_table?(config) do
    query!(config, "SELECT to_regclass('regents_app.schema_migrations') IS NOT NULL").rows == [
      [true]
    ]
  end

  # A bounded lock timeout is what makes the comparison observable rather than a
  # hang: whichever read asks for the held lock is cancelled by PostgreSQL, and
  # the read that never asks for it is untouched.
  defp with_lock_timeout(config) do
    Keyword.put(config, :after_connect, {Postgrex, :query!, ["SET lock_timeout = '500ms'", []]})
  end

  # Ecto's Postgres adapter takes the migration lock as SHARE UPDATE EXCLUSIVE
  # on the migration table inside a transaction, so holding that exact lock from
  # another connection is what an in-flight migration looks like to any other
  # reader. The lock conflicts with itself and with nothing this listing does.
  defp hold_migration_lock(config) do
    owner = self()

    holder =
      spawn(fn ->
        {:ok, connection} = Postgrex.start_link(config)

        Postgrex.transaction(
          connection,
          fn transaction ->
            Postgrex.query!(
              transaction,
              "LOCK TABLE regents_app.schema_migrations IN SHARE UPDATE EXCLUSIVE MODE",
              []
            )

            send(owner, :migration_lock_held)

            receive do
              :release_migration_lock -> :ok
            end
          end,
          timeout: :infinity
        )

        GenServer.stop(connection)
      end)

    on_exit(fn -> release_migration_lock(holder) end)
    assert_receive :migration_lock_held, 30_000
    :ok
  end

  # The disposable database cannot be dropped while this connection is open, so
  # the holder is gone before the teardown that created it runs.
  defp release_migration_lock(holder) do
    monitor = Process.monitor(holder)
    send(holder, :release_migration_lock)

    receive do
      {:DOWN, ^monitor, :process, ^holder, _reason} -> :ok
    after
      30_000 -> raise "the migration lock holder outlived the case that took it"
    end
  end

  # The listing's read with the migration lock left in, and nothing else changed.
  defp locking_migration_status(config) do
    with_config(config, fn ->
      {:ok, migrations, _started} =
        Ecto.Migrator.with_repo(AshPlatform.Repo, fn repo ->
          Ecto.Migrator.migrations(repo, [release_migrations_path()],
            prefix: repo.default_prefix(),
            skip_table_creation: true
          )
        end)

      migrations
    end)
  end

  defp query!(config, sql, params \\ []) do
    with_config(config, fn ->
      {:ok, result, _started} =
        Ecto.Migrator.with_repo(AshPlatform.Repo, fn repo ->
          Ecto.Adapters.SQL.query!(repo, sql, params)
        end)

      result
    end)
  end

  defp with_config(config, fun) do
    previous = Application.get_env(:ash_platform, AshPlatform.Repo)
    Application.put_env(:ash_platform, AshPlatform.Repo, config)

    try do
      fun.()
    after
      if previous,
        do: Application.put_env(:ash_platform, AshPlatform.Repo, previous),
        else: Application.delete_env(:ash_platform, AshPlatform.Repo)
    end
  end
end
