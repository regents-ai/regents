defmodule AshPlatformWeb.FormationLiveTest.SeedAdapter do
  @state_key {__MODULE__, :state}

  def with_state(state, fun) do
    previous = Process.get(@state_key, :missing)
    Process.put(@state_key, state)

    try do
      fun.()
    after
      if previous == :missing do
        Process.delete(@state_key)
      else
        Process.put(@state_key, previous)
      end
    end
  end

  def current! do
    Process.get(@state_key) || raise "seed adapter state is not initialized"
  end

  def transaction(fun) do
    before = current!()

    try do
      {:ok, fun.()}
    rescue
      exception ->
        Process.put(@state_key, before)
        reraise exception, __STACKTRACE__
    end
  end

  def find_accounts_by_privy_id(privy_user_id) do
    Enum.filter(current!().accounts, fn [_id, did, _wallet, _wallets] -> did == privy_user_id end)
  end

  def insert_account(privy_user_id, wallet_address) do
    state = current!()
    account_id = state.next_account_id

    Process.put(
      @state_key,
      state
      |> Map.update!(
        :accounts,
        &(&1 ++ [[account_id, privy_user_id, wallet_address, [wallet_address]]])
      )
      |> Map.update!(:next_account_id, &(&1 + 1))
    )

    [[account_id]]
  end

  def find_regents(account_id, slug) do
    Enum.filter(current!().regents, fn [_id, row_slug, _display_name, owner_id] ->
      owner_id == account_id or row_slug == slug
    end)
  end

  def insert_regent(slug, display_name, account_id) do
    state = current!()
    regent_id = state.next_regent_id

    Process.put(
      @state_key,
      state
      |> Map.update!(:regents, &(&1 ++ [[regent_id, slug, display_name, account_id]]))
      |> Map.update!(:next_regent_id, &(&1 + 1))
    )

    [[regent_id]]
  end
end

defmodule AshPlatformWeb.FormationLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatformWeb.FormationLiveTest.SeedAdapter
  alias Mix.Tasks.AshPlatform.SeedBrowserAutolaunchDraftOwner, as: SeedDraftOwner

  @fixture_token "valid-autolaunch-draft"
  @regent_slug "draft-browser-regent"
  @regent_display_name "Draft Browser Regent"
  @autolaunch_tables ~w(auctions bids launch_drafts launch_jobs payment_links subjects subject_actions tokens)

  test "Formation exposes the exact Nous handoff with one heading and no local controls", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/formation")
    html = view |> render_async() |> normalize_whitespace()

    assert has_element?(view, "#formation")
    assert has_element?(view, "#formation h1", "Regent runs best on Hermes")
    assert Regex.scan(~r/<h[1-6]\b/, html) |> length() == 1

    assert html =~ "Create and manage your Regent as a Hermes agent in Nous Portal."

    assert has_element?(
             view,
             ~s(#formation-nous-portal-link[href="https://portal.nousresearch.com/cloud"][target="_blank"][rel="noopener noreferrer"][aria-describedby="formation-nous-portal-disclosure"]),
             "Open Nous Portal"
           )

    assert has_element?(
             view,
             "#formation-nous-portal-disclosure",
             "Nous Portal opens in a new tab. Your Hermes agent can complete Autolaunch in their cloud runtime."
           )

    for selector <- [
          "#formation form",
          "#formation button",
          "#form-regent",
          "#update-regent-profile",
          "#provision-cloud-runtime",
          "#refresh-cloud-runtime",
          "#request-agent-pairing-code",
          "#agent-pairing",
          "#formation-cloud-runtime"
        ] do
      refute has_element?(view, selector)
    end

    for copy <- ["Form your Regent", "Hermes Skills", "Provision Sprite"] do
      refute html =~ copy
    end
  end

  test "signed-in visitors receive the same handoff without Formation actions", %{conn: conn} do
    account =
      Accounts.register_verified!(
        "did:privy:formation-handoff-signed-in",
        "0x1111111111111111111111111111111111111111",
        ["0x1111111111111111111111111111111111111111"],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/formation")

    html = view |> render_async() |> normalize_whitespace()

    assert html =~ "Regent runs best on Hermes"
    assert html =~ "Open Nous Portal"
    refute has_element?(view, "#formation", "0x1111")
    refute has_element?(view, "#formation [phx-click]")
    refute has_element?(view, "#formation [phx-submit]")
  end

  test "the exact DID seed inserts beside another account sharing its wallet", %{conn: _conn} do
    verified = fixture_identity!()
    other_account_id = 100

    initial =
      seed_state([
        [
          other_account_id,
          "did:privy:autolaunch-shared-wallet-other",
          verified.wallet_address,
          verified.wallet_addresses
        ]
      ])

    state =
      SeedAdapter.with_state(initial, fn ->
        assert :ok = SeedDraftOwner.seed!(adapter: SeedAdapter)
        SeedAdapter.current!()
      end)

    expected_privy_user_id = verified.privy_user_id
    expected_wallet_address = verified.wallet_address
    expected_wallet_addresses = verified.wallet_addresses

    assert [
             [
               account_id,
               ^expected_privy_user_id,
               ^expected_wallet_address,
               ^expected_wallet_addresses
             ]
           ] =
             Enum.filter(state.accounts, &(&1 |> Enum.at(1) == verified.privy_user_id))

    assert Enum.any?(state.accounts, &(&1 |> Enum.at(0) == other_account_id))

    assert [[_regent_id, @regent_slug, @regent_display_name, ^account_id]] =
             Enum.filter(state.regents, &(&1 |> Enum.at(1) == @regent_slug))
  end

  test "the exact DID seed is idempotent and leaves all Autolaunch state unchanged", %{
    conn: _conn
  } do
    verified = fixture_identity!()
    before = autolaunch_snapshot()

    assert :ok = SeedDraftOwner.seed!()

    first = %{
      account: account_rows(verified.privy_user_id),
      regents: regent_rows_for_slug(@regent_slug)
    }

    assert :ok = SeedDraftOwner.seed!()

    assert first == %{
             account: account_rows(verified.privy_user_id),
             regents: regent_rows_for_slug(@regent_slug)
           }

    assert before == autolaunch_snapshot()
  end

  test "the exact DID seed fails closed on mismatched wallet evidence", %{conn: _conn} do
    verified = fixture_identity!()
    wrong_wallet = "0x4444444444444444444444444444444444444444"
    initial = seed_state([[101, verified.privy_user_id, wrong_wallet, [wrong_wallet]]])

    state =
      SeedAdapter.with_state(initial, fn ->
        assert_raise RuntimeError, ~r/account or wallet evidence conflicts/, fn ->
          SeedDraftOwner.seed!(adapter: SeedAdapter)
        end

        SeedAdapter.current!()
      end)

    assert state == initial
  end

  test "the exact DID seed fails closed when wallet address evidence is not exact", %{conn: _conn} do
    verified = fixture_identity!()
    extra_wallet = "0x4444444444444444444444444444444444444444"

    initial =
      seed_state([
        [
          102,
          verified.privy_user_id,
          verified.wallet_address,
          [verified.wallet_address, extra_wallet]
        ]
      ])

    state =
      SeedAdapter.with_state(initial, fn ->
        assert_raise RuntimeError, ~r/account or wallet evidence conflicts/, fn ->
          SeedDraftOwner.seed!(adapter: SeedAdapter)
        end

        SeedAdapter.current!()
      end)

    assert state == initial
  end

  test "the exact DID seed fails closed on a different Regent owner and rolls back", %{
    conn: _conn
  } do
    verified = fixture_identity!()

    initial =
      seed_state(
        [[103, verified.privy_user_id, verified.wallet_address, verified.wallet_addresses]],
        [["regent-owner-conflict", "another-browser-regent", "Another Browser Regent", 103]]
      )

    state =
      SeedAdapter.with_state(initial, fn ->
        assert_raise RuntimeError, ~r/Regent identity conflicts/, fn ->
          SeedDraftOwner.seed!(adapter: SeedAdapter)
        end

        SeedAdapter.current!()
      end)

    assert state == initial
  end

  test "the exact DID seed fails closed on a slug owned by another account and rolls back", %{
    conn: _conn
  } do
    verified = fixture_identity!()

    initial =
      seed_state(
        [
          [
            104,
            "did:privy:autolaunch-slug-owner",
            verified.wallet_address,
            verified.wallet_addresses
          ]
        ],
        [["regent-slug-conflict", @regent_slug, @regent_display_name, 104]]
      )

    state =
      SeedAdapter.with_state(initial, fn ->
        assert_raise RuntimeError, ~r/Regent identity conflicts/, fn ->
          SeedDraftOwner.seed!(adapter: SeedAdapter)
        end

        SeedAdapter.current!()
      end)

    assert state == initial
  end

  test "the exact DID seed fails closed on a display mismatch and preserves the Regent", %{
    conn: _conn
  } do
    verified = fixture_identity!()

    initial =
      seed_state(
        [[105, verified.privy_user_id, verified.wallet_address, verified.wallet_addresses]],
        [["regent-display-conflict", @regent_slug, "Wrong Browser Regent", 105]]
      )

    state =
      SeedAdapter.with_state(initial, fn ->
        assert_raise RuntimeError, ~r/Regent identity conflicts/, fn ->
          SeedDraftOwner.seed!(adapter: SeedAdapter)
        end

        SeedAdapter.current!()
      end)

    assert state == initial
  end

  test "the browser owner seed refuses non-test or non-loopback targets before startup" do
    for {env, repo_config} <- [
          {:dev, [hostname: "127.0.0.1", database: "ash_platform_dev"]},
          {:prod, [hostname: "127.0.0.1", database: "ash_platform_test"]},
          {:test, [hostname: "db.internal", database: "ash_platform_test"]},
          {:test, [hostname: "127.0.0.1", database: "ash_platform"]}
        ] do
      assert_raise RuntimeError, ~r/refused unsafe database target/, fn ->
        SeedDraftOwner.validate_target!(env, repo_config)
      end
    end
  end

  defp fixture_identity! do
    {:ok, verified} = AshPlatform.TestPrivyVerifier.verify_access_token(@fixture_token)
    verified
  end

  defp seed_state(accounts, regents \\ []) do
    %{
      accounts: accounts,
      regents: regents,
      next_account_id: 1_000,
      next_regent_id: 2_000
    }
  end

  defp account_rows(privy_user_id) do
    sql!(
      "SELECT id, privy_user_id, wallet_address, wallet_addresses FROM platform.platform_human_users WHERE privy_user_id = $1 ORDER BY id",
      [privy_user_id]
    ).rows
  end

  defp regent_rows_for_slug(slug) do
    sql!(
      "SELECT id, slug, display_name, human_account_id FROM regents WHERE slug = $1 ORDER BY id",
      [slug]
    ).rows
  end

  defp autolaunch_snapshot do
    Enum.map(@autolaunch_tables, fn table ->
      {table, sql!("SELECT count(*) FROM autolaunch.#{table}").rows}
    end)
  end

  defp normalize_whitespace(html), do: Regex.replace(~r/\s+/, html, " ")

  defp sql!(query, params \\ []),
    do: Ecto.Adapters.SQL.query!(AshPlatform.Repo, query, params)
end
