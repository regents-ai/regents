defmodule AshPlatform.LocalAcceptanceTasksTest do
  use ExUnit.Case, async: false

  alias AshPlatform.LocalDatabaseFixture
  alias AshPlatform.TestLocalAcceptanceDatabaseAdapter, as: Adapter

  setup do
    start_supervised!(Adapter)
    :ok
  end

  test "setup prepares one exact database and reset is idempotent" do
    config = [
      hostname: "127.0.0.1",
      database: "ash_platform_acceptance_task_flow",
      username: "local_owner"
    ]

    opts = [config: config, adapter: Adapter, expected_username: "local_owner", environment: %{}]

    assert :ok = LocalDatabaseFixture.setup_local!("task_flow", opts)
    assert :ok = Adapter.add_product_activity()
    assert :ok = LocalDatabaseFixture.reset_local!("task_flow", opts)
    assert :ok = LocalDatabaseFixture.reset_local!("task_flow", opts)

    assert [
             {:create, ^config},
             {:prepare, ^config, "task_flow"},
             :product_activity,
             {:exists?, ^config},
             {:verify_owned!, ^config, "task_flow"},
             {:drop, ^config},
             {:exists?, ^config}
           ] = Adapter.calls()
  end

  test "PostgreSQL preflight accepts 14.20 and newer" do
    assert :ok = LocalDatabaseFixture.validate_postgres_version!("psql (PostgreSQL) 14.20")
    assert :ok = LocalDatabaseFixture.validate_postgres_version!("psql (PostgreSQL) 15.1")

    assert_raise RuntimeError, ~r/14.20 or newer/, fn ->
      LocalDatabaseFixture.validate_postgres_version!("psql (PostgreSQL) 14.19")
    end

    assert_raise RuntimeError, ~r/could not determine/, fn ->
      LocalDatabaseFixture.validate_postgres_version!("wrapper 99.99 psql (PostgreSQL) 14.20")
    end
  end

  test "production and remote configuration are rejected before database access" do
    config = [
      hostname: "127.0.0.1",
      database: "ash_platform_acceptance_guarded",
      username: "local_owner"
    ]

    assert_raise RuntimeError, ~r/unsafe acceptance database target/, fn ->
      LocalDatabaseFixture.setup_local!("guarded",
        config: config,
        adapter: Adapter,
        env: :prod,
        environment: %{}
      )
    end

    assert_raise RuntimeError, ~r/remote environment configuration/, fn ->
      LocalDatabaseFixture.setup_local!("guarded",
        config: config,
        adapter: Adapter,
        expected_username: "local_owner",
        env: :test,
        environment: %{"DATABASE_URL" => "postgres://remote.example/prod"}
      )
    end

    assert_raise RuntimeError, ~r/remote environment configuration/, fn ->
      LocalDatabaseFixture.setup_local!("guarded",
        config: config,
        adapter: Adapter,
        expected_username: "local_owner",
        env: :test,
        environment: %{"DATABASE_POOLED_URL" => "postgres://remote.example/prod"}
      )
    end

    assert_raise RuntimeError, ~r/mismatched run database target/, fn ->
      LocalDatabaseFixture.acceptance_database_exists!("expected_run",
        config: local_config("different_run"),
        adapter: Adapter,
        expected_username: "local_owner",
        env: :test,
        environment: acceptance_environment("expected_run")
      )
    end

    assert Adapter.calls() == []
  end

  test "a configured role that differs from the macOS user is rejected before database access" do
    config = local_config("wrong_role") |> Keyword.put(:username, "not_the_local_user")

    assert_raise RuntimeError, ~r/unsafe acceptance database target/, fn ->
      LocalDatabaseFixture.setup_local!("wrong_role",
        config: config,
        adapter: Adapter,
        env: :test,
        environment: %{}
      )
    end

    assert Adapter.calls() == []
  end

  test "an interrupted setup drops the database it just created" do
    config = local_config("interrupted")

    assert_raise RuntimeError, "preparation interrupted", fn ->
      LocalDatabaseFixture.setup_local!("interrupted",
        config: config,
        adapter: __MODULE__.FailingPrepareAdapter,
        expected_username: "local_owner",
        env: :test,
        environment: %{}
      )
    end

    assert_received :created
    assert_received :dropped
  end

  test "reset refuses a marker mismatch without dropping" do
    config = local_config("wrong_marker")

    assert_raise RuntimeError, "local acceptance database ownership marker mismatch", fn ->
      LocalDatabaseFixture.reset_local!("wrong_marker",
        config: config,
        adapter: __MODULE__.MarkerMismatchAdapter,
        expected_username: "local_owner",
        env: :test,
        environment: %{}
      )
    end

    refute_received :dropped
  end

  test "reset refuses protected rows without dropping" do
    config = local_config("protected_rows")

    assert_raise RuntimeError, "local acceptance protected dataset mirror is not empty", fn ->
      LocalDatabaseFixture.reset_local!("protected_rows",
        config: config,
        adapter: __MODULE__.ProtectedRowsAdapter,
        expected_username: "local_owner",
        env: :test,
        environment: %{}
      )
    end

    refute_received :dropped
  end

  test "ownership marker identity is independent from the recorded product baseline" do
    assert :ok =
             LocalDatabaseFixture.validate_ownership_marker!(
               [["owned", "ash_platform_acceptance_owned", "local_owner"]],
               "owned",
               "ash_platform_acceptance_owned",
               "local_owner"
             )

    for rows <- [[], [["other", "ash_platform_acceptance_owned", "local_owner"]]] do
      assert_raise RuntimeError, ~r/ownership marker mismatch/, fn ->
        LocalDatabaseFixture.validate_ownership_marker!(
          rows,
          "owned",
          "ash_platform_acceptance_owned",
          "local_owner"
        )
      end
    end
  end

  test "reset orchestration proves ownership before any cleanup and preserves exact order" do
    Process.put(:reset_steps, [])

    assert :ok =
             Mix.Tasks.AshPlatform.ResetLocal.reset!("ordered",
               preflight: fn run_id ->
                 record_reset_step({:preflight, run_id})
                 :owned
               end,
               identity_cleanup: fn opts -> record_reset_step({:identity, opts}) end,
               stop_application: fn -> record_reset_step(:stop_application) end,
               database_reset: fn run_id, opts ->
                 record_reset_step({:database, run_id, opts})
                 :ok
               end,
               cleanup_files?: false
             )

    assert Process.get(:reset_steps) == [
             {:preflight, "ordered"},
             {:identity, [preflight: :owned]},
             :stop_application,
             {:database, "ordered", []}
           ]

    Process.delete(:reset_steps)
  end

  test "an already absent acceptance database skips the application and database cleanup" do
    Process.put(:reset_steps, [])

    assert :ok =
             Mix.Tasks.AshPlatform.ResetLocal.run_reset!("already_absent",
               database_exists: fn run_id, opts ->
                 record_reset_step({:exists, run_id, opts})
                 false
               end,
               start_application: fn -> record_reset_step(:start_application) end,
               preflight: fn _run_id -> record_reset_step(:preflight) end,
               identity_cleanup: fn _opts -> record_reset_step(:identity) end,
               database_reset: fn _run_id, _opts -> record_reset_step(:database) end,
               cleanup_files: fn -> record_reset_step(:files) end
             )

    assert Process.get(:reset_steps) == [{:exists, "already_absent", []}, :files]
    Process.delete(:reset_steps)
  end

  test "a present acceptance database starts the application only after the existence check" do
    Process.put(:reset_steps, [])

    assert :ok =
             Mix.Tasks.AshPlatform.ResetLocal.run_reset!("present",
               database_exists: fn run_id, opts ->
                 record_reset_step({:exists, run_id, opts})
                 true
               end,
               start_application: fn -> record_reset_step(:start_application) end,
               preflight: fn run_id ->
                 record_reset_step({:preflight, run_id})
                 :owned
               end,
               identity_cleanup: fn opts -> record_reset_step({:identity, opts}) end,
               stop_application: fn -> record_reset_step(:stop_application) end,
               database_reset: fn run_id, opts ->
                 record_reset_step({:database, run_id, opts})
                 :ok
               end,
               cleanup_files: fn -> record_reset_step(:files) end
             )

    assert Process.get(:reset_steps) == [
             {:exists, "present", []},
             :start_application,
             {:preflight, "present"},
             {:identity, [preflight: :owned]},
             :stop_application,
             {:database, "present", []},
             :files
           ]

    Process.delete(:reset_steps)
  end

  test "acceptance database existence refuses unsafe targets before adapter access" do
    unsafe_config = [
      hostname: "remote.example",
      database: "ash_platform_acceptance_unsafe",
      username: "local_owner"
    ]

    assert_raise RuntimeError, ~r/unsafe acceptance database target/, fn ->
      LocalDatabaseFixture.acceptance_database_exists!("unsafe",
        config: unsafe_config,
        adapter: Adapter,
        expected_username: "local_owner",
        env: :test,
        environment: acceptance_environment("unsafe")
      )
    end

    assert_raise RuntimeError, ~r/remote environment configuration/, fn ->
      LocalDatabaseFixture.acceptance_database_exists!("unsafe",
        config: local_config("unsafe"),
        adapter: Adapter,
        expected_username: "local_owner",
        env: :test,
        environment:
          acceptance_environment("unsafe")
          |> Map.put("DATABASE_POOLED_URL", "postgres://remote.example/prod")
      )
    end

    for environment <- [%{}, acceptance_environment("different_run")] do
      assert_raise RuntimeError, ~r/requires exact run environment/, fn ->
        LocalDatabaseFixture.acceptance_database_exists!("expected_run",
          config: local_config("expected_run"),
          adapter: Adapter,
          expected_username: "local_owner",
          env: :test,
          environment: environment
        )
      end
    end

    assert_raise RuntimeError, ~r/unsafe acceptance database target/, fn ->
      LocalDatabaseFixture.acceptance_database_exists!("platform_human_users",
        config: local_config("platform_human_users"),
        adapter: Adapter,
        expected_username: "local_owner",
        env: :test,
        environment: acceptance_environment("platform_human_users")
      )
    end

    assert Adapter.calls() == []
  end

  test "acceptance database status errors are not treated as absence" do
    assert_raise RuntimeError, "status unavailable", fn ->
      LocalDatabaseFixture.acceptance_database_exists!("status_error",
        config: local_config("status_error"),
        adapter: __MODULE__.StatusErrorAdapter,
        expected_username: "local_owner",
        env: :test,
        environment: acceptance_environment("status_error")
      )
    end
  end

  test "reset orchestration leaves cleanup untouched when ownership preflight fails" do
    parent = self()

    assert_raise RuntimeError, "marker mismatch", fn ->
      Mix.Tasks.AshPlatform.ResetLocal.reset!("wrong_marker",
        preflight: fn _run_id -> raise "marker mismatch" end,
        identity_cleanup: fn _opts -> send(parent, :unexpected_identity_cleanup) end,
        database_reset: fn _run_id, _opts -> send(parent, :unexpected_database_reset) end,
        cleanup_files?: false
      )
    end

    refute_received :unexpected_identity_cleanup
    refute_received :unexpected_database_reset
  end

  test "exported reset refuses every injected cleanup option outside test" do
    parent = self()
    original_env = Mix.env()

    injected_options = [
      preflight: fn _run_id -> send(parent, :preflight_called) end,
      identity_cleanup: fn _opts -> send(parent, :identity_called) end,
      database_reset: fn _run_id, _opts -> send(parent, :database_called) end,
      stop_application: fn -> send(parent, :stop_called) end,
      cleanup_files?: false
    ]

    try do
      Mix.env(:prod)

      Enum.each(injected_options, fn {key, value} ->
        assert_raise RuntimeError, "local acceptance reset refused injected cleanup", fn ->
          Mix.Tasks.AshPlatform.ResetLocal.reset!("injected", [{key, value}])
        end
      end)
    after
      Mix.env(original_env)
    end

    refute_received :preflight_called
    refute_received :identity_called
    refute_received :database_called
    refute_received :stop_called
  end

  test "exported reset orchestrator refuses every injected option outside test" do
    parent = self()
    original_env = Mix.env()

    injected_options = [
      database_exists: fn _run_id, _opts -> send(parent, :database_exists_called) end,
      start_application: fn -> send(parent, :start_application_called) end,
      preflight: fn _run_id -> send(parent, :orchestrator_preflight_called) end,
      identity_cleanup: fn _opts -> send(parent, :orchestrator_identity_called) end,
      database_reset: fn _run_id, _opts -> send(parent, :orchestrator_database_called) end,
      stop_application: fn -> send(parent, :orchestrator_stop_called) end,
      cleanup_files: fn -> send(parent, :cleanup_files_called) end
    ]

    try do
      Mix.env(:prod)

      Enum.each(injected_options, fn {key, value} ->
        assert_raise RuntimeError, "local acceptance reset refused injected orchestration", fn ->
          Mix.Tasks.AshPlatform.ResetLocal.run_reset!("injected", [{key, value}])
        end
      end)
    after
      Mix.env(original_env)
    end

    refute_received :database_exists_called
    refute_received :start_application_called
    refute_received :orchestrator_preflight_called
    refute_received :orchestrator_identity_called
    refute_received :orchestrator_database_called
    refute_received :orchestrator_stop_called
    refute_received :cleanup_files_called
  end

  defp local_config(run_id) do
    [
      hostname: "127.0.0.1",
      database: "ash_platform_acceptance_#{run_id}",
      username: "local_owner"
    ]
  end

  defp acceptance_environment(run_id) do
    %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id}
  end

  defp record_reset_step(step) do
    Process.put(:reset_steps, Process.get(:reset_steps, []) ++ [step])
    :ok
  end

  defmodule FailingPrepareAdapter do
    def create(_config) do
      send(self(), :created)
      :ok
    end

    def prepare(_config, _run_id), do: raise("preparation interrupted")

    def drop(_config) do
      send(self(), :dropped)
      :ok
    end
  end

  defmodule MarkerMismatchAdapter do
    def exists?(_config), do: true

    def verify_owned!(_config, _run_id),
      do: raise("local acceptance database ownership marker mismatch")

    def drop(_config) do
      send(self(), :dropped)
      :ok
    end
  end

  defmodule ProtectedRowsAdapter do
    def exists?(_config), do: true

    def verify_owned!(_config, _run_id),
      do: raise("local acceptance protected dataset mirror is not empty")

    def drop(_config) do
      send(self(), :dropped)
      :ok
    end
  end

  defmodule StatusErrorAdapter do
    def exists?(_config), do: raise("status unavailable")
  end
end
