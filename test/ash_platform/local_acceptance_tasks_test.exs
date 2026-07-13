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

    opts = [config: config, adapter: Adapter]

    assert :ok = LocalDatabaseFixture.setup_local!("task_flow", opts)
    assert :ok = LocalDatabaseFixture.reset_local!("task_flow", opts)
    assert :ok = LocalDatabaseFixture.reset_local!("task_flow", opts)

    assert [
             {:create, ^config},
             {:prepare, ^config, "task_flow"},
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
        env: :test,
        environment: %{"DATABASE_URL" => "postgres://remote.example/prod"}
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
        env: :test,
        environment: %{}
      )
    end

    refute_received :dropped
  end

  defp local_config(run_id) do
    [
      hostname: "127.0.0.1",
      database: "ash_platform_acceptance_#{run_id}",
      username: "local_owner"
    ]
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
end
