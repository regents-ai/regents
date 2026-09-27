defmodule Regents.LocalDatabaseFixtureTest do
  use ExUnit.Case, async: true

  alias Regents.LocalDatabaseFixture

  test "accepts only loopback dev and test database targets" do
    assert :ok =
             LocalDatabaseFixture.validate_target!(:dev,
               hostname: "127.0.0.1",
               database: "regents_dev"
             )

    assert :ok =
             LocalDatabaseFixture.validate_target!(:test,
               hostname: "::1",
               database: "regents_test"
             )

    for {env, host, database} <- [
          {:prod, "127.0.0.1", "regents_dev"},
          {:dev, "db.internal", "regents_dev"},
          {:dev, "localhost", "regents_dev"},
          {:dev, "127.0.0.1", "regents"}
        ] do
      assert_raise RuntimeError, ~r/refused unsafe database target/, fn ->
        LocalDatabaseFixture.validate_target!(env, hostname: host, database: database)
      end
    end
  end
end
