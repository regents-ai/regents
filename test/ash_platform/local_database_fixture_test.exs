defmodule AshPlatform.LocalDatabaseFixtureTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.LocalDatabaseFixture
  alias Mix.Tasks.AshPlatform.ResetBrowserComments
  alias Mix.Tasks.AshPlatform.SeedBrowserComments

  test "the Marimo source keeps its canonical fixture path and bytes" do
    canonical_path = "test/support/fixtures/marimo_browser_notebook.py"

    assert File.regular?(canonical_path)
    refute File.exists?("test/support/marimo_browser_notebook.py")

    assert canonical_path
           |> File.read!()
           |> then(&:crypto.hash(:sha256, &1))
           |> Base.encode16(case: :lower) ==
             "5c838fe5dfb6c80757536d221ce12e9324fcf97053c9d62e61faa3490e2c544b"

    assert File.read!("test/support/test_marimo_artifact.ex") =~
             "Path.expand(\"fixtures/marimo_browser_notebook.py\", __DIR__)"
  end

  test "accepts only loopback dev and test database targets" do
    assert :ok =
             LocalDatabaseFixture.validate_target!(:dev,
               hostname: "127.0.0.1",
               database: "ash_platform_dev"
             )

    assert :ok =
             LocalDatabaseFixture.validate_target!(:test,
               hostname: "localhost",
               database: "ash_platform_test"
             )

    for {env, host, database} <- [
          {:prod, "127.0.0.1", "ash_platform_dev"},
          {:dev, "db.internal", "ash_platform_dev"},
          {:dev, "127.0.0.1", "ash_platform"}
        ] do
      assert_raise RuntimeError, ~r/refused unsafe database target/, fn ->
        LocalDatabaseFixture.validate_target!(env, hostname: host, database: database)
      end
    end
  end

  test "acceptance targets require the exact disposable local tuple" do
    local_username = "local_owner"

    assert :ok =
             LocalDatabaseFixture.validate_acceptance_target!(
               :test,
               [
                 hostname: "127.0.0.1",
                 database: "ash_platform_acceptance_safe_run_1",
                 username: local_username
               ],
               local_username
             )

    for repo <- [
          [
            hostname: "db.internal",
            database: "ash_platform_acceptance_safe_run",
            username: local_username
          ],
          [
            hostname: "127.0.0.1",
            database: "ash_platform_acceptance_safe_run",
            username: "postgres"
          ],
          [
            hostname: "127.0.0.1",
            database: "ash_platform_test",
            username: local_username
          ],
          [
            hostname: "127.0.0.1",
            database: "platform_human_users",
            username: local_username
          ]
        ] do
      assert_raise RuntimeError, ~r/refused unsafe acceptance database target/, fn ->
        LocalDatabaseFixture.validate_acceptance_target!(:test, repo, local_username)
      end
    end

    for protected <- ~w(
          platform_human_users
          basenames_mints
          basenames_mint_allowances
          basenames_payment_credits
        ),
        database <- [protected, "ash_platform_acceptance_#{protected}-unsafe"] do
      assert_raise RuntimeError, ~r/refused unsafe acceptance database target/, fn ->
        LocalDatabaseFixture.validate_acceptance_target!(
          :test,
          [hostname: "127.0.0.1", database: database, username: local_username],
          local_username
        )
      end
    end
  end

  test "browser fixtures seed, appear publicly, reset, and remain absent", %{conn: conn} do
    ResetBrowserComments.reset!()
    assert [] == public_nodes(conn)

    SeedBrowserComments.seed!()
    assert length(public_nodes(conn)) == 2

    assert ResetBrowserComments.reset!() == 2
    assert [] == public_nodes(conn)
    assert ResetBrowserComments.reset!() == 0
  end

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
      "INSERT INTO techtree.nodes (id, tree_id, title, summary, published_at, inserted_at, updated_at) SELECT $1, id, 'Unrelated', 'Keep me', now(), now(), now() FROM techtree.trees WHERE slug = 'skill-training-lab'",
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
        ResetBrowserComments.reset!(env: env, repo_config: config)
      end
    end
  end

  test "browser fixture reset aborts when a titled row does not match the complete marker" do
    ResetBrowserComments.reset!()

    sql!(
      "INSERT INTO techtree.nodes (tree_id, title, summary, published_at, inserted_at, updated_at) SELECT id, 'Browser comment fixture', 'Not owned', now(), now(), now() FROM techtree.trees WHERE slug = 'skill-training-lab'"
    )

    assert_raise RuntimeError, ~r/marker mismatch/, fn -> ResetBrowserComments.reset!() end
  end

  test "browser fixture reset aborts when a complete marker is ambiguous" do
    ResetBrowserComments.reset!()
    SeedBrowserComments.seed!()

    sql!(
      "INSERT INTO techtree.nodes (tree_id, title, summary, payload_hash, published_at, inserted_at, updated_at) SELECT id, 'Browser notebook fixture', 'A local Marimo notebook running on this device.', 'sha256:browser-notebook-node-payload', now(), now(), now() FROM techtree.trees WHERE slug = 'skill-training-lab'"
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
