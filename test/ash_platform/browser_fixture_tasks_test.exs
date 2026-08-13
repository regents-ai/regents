defmodule AshPlatform.BrowserFixtureTasksTest do
  use AshPlatformWeb.ConnCase, async: false

  alias Mix.Tasks.AshPlatform.ResetBrowserComments
  alias Mix.Tasks.AshPlatform.SeedBrowserComments

  @tag :external
  test "browser fixtures seed, appear publicly, reset, and remain absent", %{conn: conn} do
    ResetBrowserComments.reset!()
    assert [] == public_nodes(conn)

    SeedBrowserComments.seed!()
    assert length(public_nodes(conn)) == 2

    assert ResetBrowserComments.reset!() == 2
    assert [] == public_nodes(conn)
    assert ResetBrowserComments.reset!() == 0
  end

  @tag :external
  test "browser fixture reset removes owned dependencies and preserves unrelated rows" do
    ResetBrowserComments.reset!()
    SeedBrowserComments.seed!()

    [[fixture_id]] =
      sql!("SELECT id FROM techtree.nodes WHERE title = 'Browser comment fixture'").rows

    [[author_id]] =
      sql!("SELECT id FROM platform.platform_human_users ORDER BY id LIMIT 1").rows

    unrelated_id = database_uuid()
    comment_id = database_uuid()

    sql!(
      "INSERT INTO techtree.nodes (id, tree_id, title, summary, workflow_state, published_at, inserted_at, updated_at) SELECT $1, id, 'Unrelated', 'Keep me', 'published', now(), now(), now() FROM techtree.trees WHERE slug = 'skill-training-lab'",
      [unrelated_id]
    )

    sql!(
      "INSERT INTO discussions.comments (id, target_type, target_id, body, client_request_id, author_id, inserted_at, updated_at) VALUES ($1, 'techtree_node', $2, 'Owned', $3, $4, now(), now())",
      [comment_id, fixture_id, database_uuid(), author_id]
    )

    sql!(
      "INSERT INTO discussions.comment_reactions (id, comment_id, reactor_id, value, inserted_at, updated_at) VALUES ($1, $2, $3, 'useful', now(), now())",
      [database_uuid(), comment_id, author_id]
    )

    assert ResetBrowserComments.reset!() == 2

    assert [[0]] ==
             sql!("SELECT count(*) FROM discussions.comments WHERE id = $1", [comment_id]).rows

    assert [[0]] ==
             sql!("SELECT count(*) FROM discussions.comment_reactions WHERE comment_id = $1", [
               comment_id
             ]).rows

    assert [[1]] == sql!("SELECT count(*) FROM techtree.nodes WHERE id = $1", [unrelated_id]).rows
  end

  test "browser fixture reset refuses non-test targets" do
    for {env, config} <- [
          {:dev, [hostname: "127.0.0.1", database: "ash_platform_dev"]},
          {:prod, [hostname: "127.0.0.1", database: "ash_platform_test"]},
          {:test, [hostname: "db.internal", database: "ash_platform_test"]}
        ] do
      assert_raise RuntimeError, ~r/refused unsafe database target/, fn ->
        ResetBrowserComments.reset!(env: env, repo_config: config, environment: %{})
      end
    end
  end

  test "browser fixture reset aborts when a titled row does not match the complete marker" do
    ResetBrowserComments.reset!()

    sql!(
      "INSERT INTO techtree.nodes (tree_id, title, summary, workflow_state, published_at, inserted_at, updated_at) SELECT id, 'Browser comment fixture', 'Not owned', 'published', now(), now(), now() FROM techtree.trees WHERE slug = 'skill-training-lab'"
    )

    assert_raise RuntimeError, ~r/marker mismatch/, fn -> ResetBrowserComments.reset!() end
  end

  @tag :external
  test "browser fixture reset aborts when a complete marker is ambiguous" do
    ResetBrowserComments.reset!()
    SeedBrowserComments.seed!()

    sql!(
      "INSERT INTO techtree.nodes (tree_id, title, summary, payload_hash, workflow_state, published_at, inserted_at, updated_at) SELECT id, 'Browser notebook fixture', 'A local Marimo notebook running on this device.', 'sha256:browser-notebook-node-payload', 'published', now(), now(), now() FROM techtree.trees WHERE slug = 'skill-training-lab'"
    )

    assert_raise RuntimeError, ~r/ambiguous browser fixture marker/, fn ->
      ResetBrowserComments.reset!()
    end
  end

  defp public_nodes(conn) do
    conn
    |> Phoenix.ConnTest.get("/api/techtree/v1/tree/nodes")
    |> Phoenix.ConnTest.json_response(200)
    |> Map.fetch!("data")
  end

  defp sql!(sql, params \\ []), do: Ecto.Adapters.SQL.query!(AshPlatform.Repo, sql, params)

  defp database_uuid, do: Ecto.UUID.generate() |> Ecto.UUID.dump!()
end
