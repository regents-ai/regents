defmodule AshPlatform.LocalDatabaseFixtureTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.LocalDatabaseFixture
  alias Mix.Tasks.AshPlatform.ResetBrowserComments
  alias Mix.Tasks.AshPlatform.ResetBrowserIdentity
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

  test "human-account setup admits only the fully guarded acceptance target" do
    owner = System.fetch_env!("USER")
    run_id = "u3_guarded_fixture"

    safe_repo = [
      hostname: "127.0.0.1",
      database: "ash_platform_acceptance_#{run_id}",
      username: owner
    ]

    parent = self()

    setup = fn ->
      send(parent, :fixture_setup)
      :ok
    end

    assert :ok =
             LocalDatabaseFixture.ensure_human_accounts!(
               repo: safe_repo,
               env: :test,
               environment: %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id},
               setup: setup
             )

    assert_receive :fixture_setup

    unsafe_cases = [
      {safe_repo, %{}},
      {safe_repo, %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => "wrong_run"}},
      {Keyword.put(safe_repo, :username, "wrong_role"),
       %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id}},
      {Keyword.put(safe_repo, :hostname, "db.internal"),
       %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id}},
      {Keyword.put(safe_repo, :database, "ash_platform_acceptance_platform_human_users"),
       %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => "platform_human_users"}},
      {safe_repo,
       %{
         "ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id,
         "DATABASE_POOLED_URL" => "postgres://remote.invalid/db"
       }}
    ]

    for {repo, environment} <- unsafe_cases do
      ref = make_ref()

      assert_raise RuntimeError, fn ->
        LocalDatabaseFixture.ensure_human_accounts!(
          repo: repo,
          env: :test,
          environment: environment,
          setup: fn -> send(parent, {:unexpected_setup, ref}) end
        )
      end

      refute_received {:unexpected_setup, ^ref}
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

    unrelated_id = database_uuid()
    comment_id = database_uuid()
    author_privy_id = "did:privy:browser-reset-#{Ecto.UUID.generate()}"

    [[author_id]] =
      sql!(
        "INSERT INTO platform.platform_human_users (privy_user_id, created_at, updated_at) VALUES ($1, now(), now()) RETURNING id",
        [author_privy_id]
      ).rows

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

    sql!("DELETE FROM platform.platform_human_users WHERE id = $1", [author_id])
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

  test "browser fixture reset admits only its exact guarded acceptance target" do
    owner = System.fetch_env!("USER")
    run_id = "u3_reset_guard"

    repo = [
      hostname: "127.0.0.1",
      database: "ash_platform_acceptance_#{run_id}",
      username: owner
    ]

    assert :ok =
             ResetBrowserComments.validate_test_target!(
               :test,
               repo,
               %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id}
             )

    for {unsafe_repo, environment} <- [
          {repo, %{}},
          {repo, %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => "wrong_run"}},
          {Keyword.put(repo, :username, "wrong_role"),
           %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id}},
          {Keyword.put(repo, :hostname, "db.internal"),
           %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id}},
          {Keyword.put(repo, :database, "ash_platform_acceptance_platform_human_users"),
           %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => "platform_human_users"}},
          {repo,
           %{
             "ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id,
             "DATABASE_DIRECT_URL" => "postgres://remote.invalid/db"
           }}
        ] do
      assert_raise RuntimeError, fn ->
        ResetBrowserComments.validate_test_target!(:test, unsafe_repo, environment)
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

  test "browser identity cleanup is run-owned, ordered, and idempotent" do
    owner = System.fetch_env!("USER")
    run_id = "u3_identity_cleanup"
    repo = acceptance_repo(run_id, owner)
    identity = owned_browser_identity()

    Process.put(:browser_identity_fixture, %{
      marker_rows: [[run_id, "ash_platform_acceptance_#{run_id}", owner]],
      identities: [
        [42, identity.privy_user_id, identity.wallet_address, identity.wallet_addresses],
        [77, "did:privy:unrelated", "0x7777777777777777777777777777777777777777", []]
      ],
      regents: [{101, 42}, {202, 77}],
      delete_identity_result: 1
    })

    did = identity.privy_user_id

    assert %{regents: 1, identities: 1} =
             ResetBrowserIdentity.reset!(
               env: :test,
               repo_config: repo,
               environment: %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id},
               adapter: __MODULE__.BrowserIdentityAdapter,
               owned_identity: identity
             )

    assert_received :ownership_marker_rows
    assert_received {:identity_rows, ^did}
    assert_received {:delete_regents, 42}
    assert_received {:delete_identity, 42, ^did}

    assert %{identities: [[77, "did:privy:unrelated", _, _]], regents: [{202, 77}]} =
             Process.get(:browser_identity_fixture)

    Process.put(:browser_identity_fixture, %{
      marker_rows: [[run_id, "ash_platform_acceptance_#{run_id}", owner]],
      identities: [],
      regents: [],
      delete_identity_result: 1
    })

    assert %{regents: 0, identities: 0} =
             ResetBrowserIdentity.reset!(
               env: :test,
               repo_config: repo,
               environment: %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id},
               adapter: __MODULE__.BrowserIdentityAdapter,
               owned_identity: identity
             )

    refute_received {:delete_regents, _}
    refute_received {:delete_identity, _, _}
    Process.delete(:browser_identity_fixture)
  end

  test "browser identity cleanup refuses unsafe targets and mismatched evidence before writes" do
    owner = System.fetch_env!("USER")
    run_id = "u3_identity_guard"
    repo = acceptance_repo(run_id, owner)
    identity = owned_browser_identity()

    unsafe = [
      {:prod, repo, %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id}},
      {:test, Keyword.put(repo, :hostname, "db.internal"),
       %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id}},
      {:test, repo, %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => "wrong_run"}},
      {:test, repo, %{}},
      {:test, repo,
       %{
         "ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id,
         "DATABASE_URL" => "postgres://remote.invalid/prod"
       }}
    ]

    for {env, unsafe_repo, environment} <- unsafe do
      assert_raise RuntimeError, fn ->
        ResetBrowserIdentity.reset!(
          env: env,
          repo_config: unsafe_repo,
          environment: environment,
          adapter: __MODULE__.BrowserIdentityAdapter,
          owned_identity: identity
        )
      end
    end

    refute_received :ownership_marker_rows
    refute_received {:delete_regents, _}
    refute_received {:delete_identity, _, _}

    Process.put(:browser_identity_fixture, %{
      marker_rows: [],
      identities: [
        [42, identity.privy_user_id, identity.wallet_address, identity.wallet_addresses]
      ],
      regents: [{101, 42}],
      delete_identity_result: 1
    })

    assert_raise RuntimeError, ~r/ownership marker mismatch/, fn ->
      ResetBrowserIdentity.reset!(
        env: :test,
        repo_config: repo,
        environment: %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id},
        adapter: __MODULE__.BrowserIdentityAdapter,
        owned_identity: identity
      )
    end

    refute_received {:identity_rows, _}
    refute_received {:delete_regents, _}
    refute_received {:delete_identity, _, _}

    Process.put(:browser_identity_fixture, %{
      marker_rows: [[run_id, "ash_platform_acceptance_#{run_id}", owner]],
      identities: [
        [
          42,
          identity.privy_user_id,
          "0x2222222222222222222222222222222222222222",
          identity.wallet_addresses
        ]
      ],
      regents: [{101, 42}],
      delete_identity_result: 1
    })

    assert_raise RuntimeError, ~r/mismatched run-owned identity evidence/, fn ->
      ResetBrowserIdentity.reset!(
        env: :test,
        repo_config: repo,
        environment: %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id},
        adapter: __MODULE__.BrowserIdentityAdapter,
        owned_identity: identity
      )
    end

    refute_received {:delete_regents, _}
    refute_received {:delete_identity, _, _}

    Process.put(:browser_identity_fixture, %{
      marker_rows: [[run_id, "ash_platform_acceptance_#{run_id}", owner]],
      identities: [
        [42, identity.privy_user_id, identity.wallet_address, identity.wallet_addresses],
        [43, identity.privy_user_id, identity.wallet_address, identity.wallet_addresses]
      ],
      regents: [{101, 42}, {102, 43}],
      delete_identity_result: 1
    })

    assert_raise RuntimeError, ~r/ambiguous run-owned identity/, fn ->
      ResetBrowserIdentity.reset!(
        env: :test,
        repo_config: repo,
        environment: %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id},
        adapter: __MODULE__.BrowserIdentityAdapter,
        owned_identity: identity
      )
    end

    refute_received {:delete_regents, _}
    refute_received {:delete_identity, _, _}

    Process.put(:browser_identity_fixture, %{
      marker_rows: [[run_id, "ash_platform_acceptance_#{run_id}", owner]],
      identities: [
        [42, identity.privy_user_id, identity.wallet_address, identity.wallet_addresses]
      ],
      regents: [{101, 42}],
      delete_identity_result: 0
    })

    assert_raise RuntimeError, ~r/could not remove the run-owned identity/, fn ->
      ResetBrowserIdentity.reset!(
        env: :test,
        repo_config: repo,
        environment: %{"ASH_PLATFORM_ACCEPTANCE_RUN_ID" => run_id},
        adapter: __MODULE__.BrowserIdentityAdapter,
        owned_identity: identity
      )
    end

    assert %{identities: [[42, _, _, _]], regents: [{101, 42}]} =
             Process.get(:browser_identity_fixture)

    Process.delete(:browser_identity_fixture)
  end

  defp public_nodes(conn) do
    conn
    |> Phoenix.ConnTest.get("/api/techtree/v1/tree/nodes")
    |> Phoenix.ConnTest.json_response(200)
    |> Map.fetch!("data")
  end

  defp sql!(sql, params \\ []), do: Ecto.Adapters.SQL.query!(AshPlatform.Repo, sql, params)

  defp database_uuid, do: Ecto.UUID.generate() |> Ecto.UUID.dump!()

  defp acceptance_repo(run_id, owner) do
    [
      hostname: "127.0.0.1",
      database: "ash_platform_acceptance_#{run_id}",
      username: owner
    ]
  end

  defp owned_browser_identity do
    %{
      privy_user_id: "did:privy:verified",
      wallet_address: "0x1111111111111111111111111111111111111111",
      wallet_addresses: ["0x1111111111111111111111111111111111111111"]
    }
  end

  defmodule BrowserIdentityAdapter do
    def transaction(fun) do
      before = Process.get(:browser_identity_fixture)

      try do
        {:ok, fun.()}
      rescue
        error ->
          Process.put(:browser_identity_fixture, before)
          reraise error, __STACKTRACE__
      end
    end

    def ownership_marker_rows do
      send(self(), :ownership_marker_rows)
      Process.get(:browser_identity_fixture).marker_rows
    end

    def identity_rows(privy_user_id) do
      send(self(), {:identity_rows, privy_user_id})

      Process.get(:browser_identity_fixture).identities
      |> Enum.filter(fn [_id, did, _wallet, _wallets] -> did == privy_user_id end)
      |> Enum.map(fn [id, _did, wallet, wallets] -> [id, wallet, wallets] end)
    end

    def delete_regents(account_id) do
      send(self(), {:delete_regents, account_id})
      fixture = Process.get(:browser_identity_fixture)

      {owned, unrelated} =
        Enum.split_with(fixture.regents, fn {_id, owner_id} -> owner_id == account_id end)

      Process.put(:browser_identity_fixture, %{fixture | regents: unrelated})
      length(owned)
    end

    def delete_identity(account_id, privy_user_id) do
      send(self(), {:delete_identity, account_id, privy_user_id})
      fixture = Process.get(:browser_identity_fixture)

      if fixture.delete_identity_result == 1 do
        remaining =
          Enum.reject(fixture.identities, fn [id, did, _wallet, _wallets] ->
            id == account_id and did == privy_user_id
          end)

        Process.put(:browser_identity_fixture, %{fixture | identities: remaining})
      end

      fixture.delete_identity_result
    end
  end
end
