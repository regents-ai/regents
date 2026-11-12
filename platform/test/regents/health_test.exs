defmodule Regents.HealthTest do
  # Invariant: the health answer says when a release carries a migration its
  # database has not applied, and still answers 200, so the host keeps serving.
  # Ported from ash-template's health_test.exs.
  use RegentsWeb.ConnCase, async: true

  test "a database with every migration applied says so", %{conn: conn} do
    assert Regents.Health.migrations_applied?()

    assert %{"status" => "ok", "migrations_applied" => true} =
             conn |> get("/api/v1/health") |> json_response(200)
  end

  test "a migration the database has not recorded leaves the answer at 200 and says so", %{
    conn: conn
  } do
    # Forget the newest applied migration inside this test's own transaction.
    Ecto.Adapters.SQL.query!(
      Regents.Repo,
      "DELETE FROM regents_app.schema_migrations WHERE version = (SELECT max(version) FROM regents_app.schema_migrations)",
      []
    )

    refute Regents.Health.migrations_applied?()

    assert %{"status" => "ok", "migrations_applied" => false} =
             conn |> get("/api/v1/health") |> json_response(200)
  end
end
