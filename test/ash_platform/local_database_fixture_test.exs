defmodule AshPlatform.LocalDatabaseFixtureTest do
  use ExUnit.Case, async: true

  alias AshPlatform.LocalDatabaseFixture

  test "accepts only loopback dev and test database targets" do
    assert :ok =
             LocalDatabaseFixture.validate_target!(:dev,
               hostname: "127.0.0.1",
               database: "ash_platform_dev"
             )

    assert :ok =
             LocalDatabaseFixture.validate_target!(:test,
               hostname: "::1",
               database: "ash_platform_test"
             )

    for {env, host, database} <- [
          {:prod, "127.0.0.1", "ash_platform_dev"},
          {:dev, "db.internal", "ash_platform_dev"},
          {:dev, "localhost", "ash_platform_dev"},
          {:dev, "127.0.0.1", "ash_platform"}
        ] do
      assert_raise RuntimeError, ~r/refused unsafe database target/, fn ->
        LocalDatabaseFixture.validate_target!(env, hostname: host, database: database)
      end
    end
  end
end
