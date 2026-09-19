defmodule AshPlatformWeb.ShellLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.AccessContext.AccountControl
  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatformWeb.Components.Shell
  alias AshPlatformWeb.RouteCatalog

  import AshPlatform.NamesFixtures

  setup_all do
    ensure_claims_table!()
  end

  test "an anonymous visitor to /account is asked to sign in, without private content", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/account")

    assert html =~ ~s(id="app-shell")
    assert has_element?(view, "#route-content h1", "Account")
    assert has_element?(view, "#account-page button[data-account-target=sign-in]", "Sign in")
    refute has_element?(view, "#account-identity")
    refute has_element?(view, "#route-content .verified-connections")
  end

  test "an anonymous socket rejects a forged verified connection request", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")

    render_hook(view, "request_verified_connection", %{
      "action" => "link",
      "provider" => "x"
    })

    refute_push_event(view, "verified-connections:request", _payload)
  end

  test "direct deep links render the persistent shell and honest missing-record state", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/regents/not-here")

    assert html =~ ~s(id="app-shell")
    assert html =~ ~s(id="shell-header")
    assert html =~ ~s(id="shell-sidebar")
    assert html =~ ~s(id="app-shell-scroller")
    assert byte_size(html) <= 100 * 1024
    assert html =~ "Regent not found"
    assert render_async(view) =~ "This public Regent profile does not exist."
  end

  test "the switch states the theme the server just served", %{conn: conn} do
    {:ok, dark, _html} = live(conn, "/stake")

    assert has_element?(
             dark,
             ~s(#theme-control button.theme-toggle[aria-pressed=false][title="Switch to Light"]),
             "Dark theme active"
           )

    {:ok, light, _html} =
      conn
      |> Plug.Test.put_req_cookie("regent_theme", "light")
      |> live("/stake")

    assert has_element?(
             light,
             ~s(#theme-control button.theme-toggle[aria-pressed=true][title="Switch to Dark"]),
             "Light theme active"
           )

    assert has_element?(
             light,
             ~s(button.theme-toggle[aria-label="Color theme: Light. Activate Dark theme."])
           )
  end

  test "anonymous account control renders Sign In separately from the brand link", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")

    assert has_element?(view, ~s(#shell-brand[href="/"]), "Regents Labs")
    assert has_element?(view, "#shell-brand .shell-brand__mark img.shell-brand__mark-light")
    assert has_element?(view, "#shell-brand .shell-brand__mark img.shell-brand__mark-dark")
    refute has_element?(view, ~s(.shell-background[data-background-slot="regents_labs"]))
    assert has_element?(view, "#theme-control button.theme-toggle[data-theme-toggle]")
    assert has_element?(view, "#account-control [data-account-target=sign-in]", "Sign In")

    assert has_element?(
             view,
             "#account-control #account-auth-status[role=status][aria-live=polite][aria-atomic=true][phx-update=ignore][hidden]"
           )

    refute has_element?(view, "#account-control a", "Nous Portal")
  end

  test "signed-in account control renders its address avatar and requested menu", %{conn: conn} do
    account = register_account("signed-in-control", "0x1111111111111111111111111111111111111111")

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    assert has_element?(view, "#account-control [data-account-target=profile]", "0x1111…1111")

    assert has_element?(
             view,
             "#account-control img.account-avatar[src^='data:image/svg+xml;base64,']"
           )

    assert has_element?(
             view,
             "#account-control button[type=button][data-account-target=sign-out]",
             "Disconnect"
           )

    refute has_element?(view, "#account-control [data-account-target=profile]", "Profile")
    assert has_element?(view, "#account-control a[data-account-menu-item=account]", "Account")
    assert has_element?(view, "#theme-control button.theme-toggle[data-theme-toggle]")
    refute has_element?(view, "#account-control [phx-click]")
  end

  test "stale wallet evidence cannot retain protected human shell access", %{conn: conn} do
    account =
      register_account("stale-wallet-control", "0x9999999999999999999999999999999999999999")

    assert {:ok, _invalidated} = Accounts.refresh_verified(account, nil, [], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    assert has_element?(view, "#account-control [data-account-target=sign-in]", "Sign In")
    refute has_element?(view, "#account-control [data-account-target=sign-out]", "Disconnect")
  end

  test "signed-in account presentation survives an in-shell patch", %{conn: conn} do
    account = register_account("signed-in-patch", "0x2222222222222222222222222222222222222222")

    {:ok, view, html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    pid = view.pid
    [instance] = Regex.run(~r/data-shell-instance="(\d+)"/, html, capture: :all_but_first)

    view
    |> element("#shell-sidebar a", "Stake")
    |> render_click()

    assert_patch(view, "/stake")
    assert view.pid == pid
    assert render(view) =~ ~s(data-shell-instance="#{instance}")
    assert has_element?(view, "#account-control [data-account-target=profile]", "0x2222…2222")
    assert has_element?(view, "#account-control [data-account-target=sign-out]", "Disconnect")
  end

  test "account control renders Profile only for a server-supplied canonical path" do
    html =
      render_shell(%AccountControl{
        kind: :signed_in,
        label: "Ada.regent.eth",
        profile_path: "/regents/ada",
        avatar_src: "data:image/svg+xml;base64,PHN2Zy8+"
      })

    assert html =~ ~s(data-account-target="profile")
    assert html =~ ~s(href="/regents/ada")
    assert html =~ ~r/>\s*Profile\s*<\/a>/
    assert html =~ ~s(class="account-avatar")
    assert html =~ ~s(src="data:image/svg+xml;base64,PHN2Zy8+")
    assert html =~ ~s(href="/account")
    assert html =~ ~s(data-account-menu-item="account")
    assert html =~ "Disconnect"
    refute html =~ "Sign Out"
  end

  test "an open page takes the ENS name as soon as the chain answers", %{conn: conn} do
    account =
      register_account(
        "ens-late-arrival",
        AshPlatform.TestEnsChainClient.wallet(:named_with_avatar)
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    assert has_element?(view, "#account-control [data-account-target=profile]", "0xaaaa…0001")

    Phoenix.PubSub.subscribe(AshPlatform.PubSub, AshPlatform.Ens.topic(account.id))
    assert AshPlatform.Ens.refresh(account) == :started
    assert_receive {:ens_lookup_finished, _account_id}, 2_000

    assert render(view) =~ ~s(src="https://avatars.regents.test/atlas.png")
    assert has_element?(view, "#account-control [data-account-target=profile]", "atlas.eth")
  end

  test "the account chip shows the wallet's ENS name and picture" do
    html =
      render_shell(%AccountControl{
        kind: :signed_in,
        label: "atlas.eth",
        profile_path: nil,
        avatar_src: "https://avatars.regents.test/atlas.png"
      })

    assert html =~ ~s(src="https://avatars.regents.test/atlas.png")
    assert html =~ ~r/data-account-target="profile">\s*atlas.eth\s*</
  end

  test "Account owns its own page rather than relabeling the whole shell" do
    html =
      render_component(&AshPlatformWeb.AccountLive.page/1, %{
        account_control: %AccountControl{kind: :sign_in, label: "Sign In", profile_path: nil}
      })

    assert html =~ ~s(id="account-page")
    assert html =~ ">Account<"
    assert html =~ "Sign in to see your account"
    refute html =~ "Verified connections"
  end

  test "Account shows the signed-in person, their wallets, names and connections", %{
    conn: conn
  } do
    wallet = "0x6666666666666666666666666666666666666666"
    other = "0x7777777777777777777777777777777777777777"
    stranger = "0x8888888888888888888888888888888888888888"

    assert {:ok, account} =
             Accounts.register_verified("did:privy:account-page", wallet, [wallet, other],
               actor: %System{}
             )

    insert_claim(1, String.upcase(wallet), %{ens_fqdn: "first.regent.eth"})
    insert_claim(2, other)
    insert_claim(3, stranger)

    Accounts.upsert_linked_identity!(
      :x,
      "account-x-subject",
      "account_user",
      "Account User",
      DateTime.utc_now(),
      %{},
      account.id,
      actor: %System{}
    )

    {view, html} = open_account(conn, account)

    refute html =~ "Sign in to see your account"
    assert has_element?(view, "#account-identity h2", "0x6666…6666")
    assert has_element?(view, "#account-identity canvas[data-holo-canvas]")
    assert has_element?(view, ".account-details code", wallet)
    assert has_element?(view, "#account-wallet-copy[data-copy-text='#{wallet}']", "Copy")
    assert has_element?(view, ".account-wallet-list code", other)
    assert has_element?(view, ".account-details dd", "No primary name set for this wallet")
    assert has_element?(view, ".account-details dd", "Not set")
    assert has_element?(view, ".account-details dd", "Not verified")
    assert has_element?(view, "#account-names-title", "Claimed Regent Names")

    assert has_element?(view, "#account-names strong", "first.regent.eth")
    assert has_element?(view, "#account-names strong", "name-2.regent.eth")
    refute render(view) =~ "agent.base.eth"
    refute render(view) =~ "name-3."
    refute has_element?(view, "#account-names-more")

    assert has_element?(
             view,
             ~s(#account-verified-connections-x a[href="https://x.com/account_user"]),
             "@account_user"
           )

    assert has_element?(view, "#account-verified-connections-x button", "Disconnect")
    assert has_element?(view, "#account-verified-connections-github", "Not connected")
    assert has_element?(view, "#account-verified-connections-github button", "Connect")
    refute render(view) =~ "account-x-subject"
    assert has_element?(view, "#account-page button[data-account-target=sign-out]", "Sign out")

    view
    |> element("#account-verified-connections-x button", "Disconnect")
    |> render_click()

    assert_push_event(view, "verified-connections:request", %{
      action: :unlink,
      provider: :x,
      subject: "account-x-subject"
    })

    assert has_element?(view, "#account-verified-connections [role=status]", "Disconnecting X")

    render_hook(view, "refresh_verified_connections", %{"error" => "already-connected"})

    assert has_element?(
             view,
             "#account-verified-connections [role=alert]",
             "already connected to another Regent account"
           )
  end

  test "a connection is only called connected once the account's own record says so", %{
    conn: conn
  } do
    wallet = "0x9999999999999999999999999999999999999999"
    account = register_account("account-outcomes", wallet)

    Accounts.upsert_linked_identity!(
      :x,
      "outcome-x-subject",
      "outcome_user",
      nil,
      DateTime.utc_now(),
      %{},
      account.id,
      actor: %System{}
    )

    {view, _html} = open_account(conn, account)

    view |> element("#account-verified-connections-github button", "Connect") |> render_click()
    assert_push_event(view, "verified-connections:request", %{action: :link, provider: :github})

    assert has_element?(
             view,
             "#account-verified-connections [role=status]",
             "Taking you to GitHub to approve the connection."
           )

    view |> element("#account-verified-connections-farcaster button", "Connect") |> render_click()

    assert has_element?(
             view,
             "#account-verified-connections [role=status]",
             "Scan the code with Farcaster to approve the connection."
           )

    # The browser says its side finished, but nothing was recorded for GitHub.
    render_hook(view, "refresh_verified_connections", %{
      "action" => "link",
      "provider" => "github"
    })

    assert has_element?(
             view,
             "#account-verified-connections [role=alert]",
             "GitHub didn’t come back connected. Try again."
           )

    # A finished disconnect whose record is still there is not a disconnection.
    render_hook(view, "refresh_verified_connections", %{"action" => "unlink", "provider" => "x"})

    assert has_element?(
             view,
             "#account-verified-connections [role=alert]",
             "X is still connected. Try again."
           )

    {:ok, identity} =
      Accounts.get_linked_identity_by_subject(:x, "outcome-x-subject", actor: %System{})

    :ok = Accounts.remove_linked_identity(identity, actor: %System{})
    render_hook(view, "refresh_verified_connections", %{"action" => "unlink", "provider" => "x"})

    assert has_element?(view, "#account-verified-connections [role=status]", "X disconnected.")
    assert has_element?(view, "#account-verified-connections-x button", "Connect")

    # A refresh that names no request (a plain sign-in refresh) re-reads quietly.
    render_hook(view, "refresh_verified_connections", %{"error" => nil})
    refute has_element?(view, "#account-verified-connections [role=status]")
    refute has_element?(view, "#account-verified-connections [role=alert]")

    # A browser-side failure is reported as one, whatever the record says.
    render_hook(view, "refresh_verified_connections", %{
      "error" => "failed",
      "action" => "link",
      "provider" => "x"
    })

    assert has_element?(
             view,
             "#account-verified-connections [role=alert]",
             "That connection couldn’t be verified. Try again."
           )
  end

  test "Account asks Ethereum for a primary name it has never read and shows it as it lands",
       %{conn: conn} do
    account =
      register_account(
        "account-ens-fresh",
        AshPlatform.TestEnsChainClient.wallet(:named_with_avatar)
      )

    Phoenix.PubSub.subscribe(AshPlatform.PubSub, AshPlatform.Ens.topic(account.id))

    {:ok, view, html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/account")

    assert html =~ "Checking Ethereum for a primary name…"
    refute html =~ "No primary name set"

    assert_receive {:ens_lookup_finished, _account_id}, 2_000
    assert has_element?(view, ".account-details dd", "atlas.eth")
    assert has_element?(view, "#account-identity h2", "atlas.eth")
    refute render(view) =~ "Checking Ethereum"
  end

  test "Account says so when Ethereum could not be asked, never that there is no name", %{
    conn: conn
  } do
    account =
      register_account("account-ens-down", AshPlatform.TestEnsChainClient.wallet(:unreachable))

    {view, _html} = open_account(conn, account)

    assert has_element?(
             view,
             ".account-details dd[role=status]",
             "Couldn’t check Ethereum right now. Refresh to try again."
           )

    refute render(view) =~ "No primary name set"
  end

  test "Account re-reads a primary name last read more than a day ago", %{conn: conn} do
    account =
      register_account(
        "account-ens-stale",
        AshPlatform.TestEnsChainClient.wallet(:named_with_avatar)
      )

    Accounts.put_ens_identity(account.id, "yesterday.eth", nil, actor: %System{})

    AshPlatform.Repo.query!(
      "update regents_app.account_ens_identities set updated_at = now() - interval '2 days' where human_account_id = $1",
      [account.id]
    )

    Phoenix.PubSub.subscribe(AshPlatform.PubSub, AshPlatform.Ens.topic(account.id))

    {:ok, view, html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/account")

    assert html =~ "yesterday.eth"
    assert_receive {:ens_lookup_finished, _account_id}, 2_000
    assert has_element?(view, ".account-details dd", "atlas.eth")
    refute render(view) =~ "yesterday.eth"
  end

  test "Account leaves a primary name read today alone", %{conn: conn} do
    account =
      register_account(
        "account-ens-today",
        AshPlatform.TestEnsChainClient.wallet(:named_with_avatar)
      )

    Accounts.put_ens_identity(account.id, "today.eth", nil, actor: %System{})
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, AshPlatform.Ens.topic(account.id))

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/account")

    assert has_element?(view, ".account-details dd", "today.eth")
    refute_receive {:ens_lookup_finished, _account_id}, 300
  end

  test "Account lists claimed names oldest first and adds the next page as the reader reaches the end",
       %{conn: conn} do
    wallet = "0x5555555555555555555555555555555555555555"
    account = register_account("account-many-names", wallet)

    for id <- 1..51 do
      insert_claim(id, wallet, %{created_at: DateTime.add(~U[2025-01-01 00:00:00Z], id, :day)})
    end

    {view, _html} = open_account(conn, account)

    assert has_element?(view, "#account-names li:first-child strong", "name-1.regent.eth")

    assert has_element?(view, "#account-names li:first-child span", "Claimed 2 January 2025")
    assert has_element?(view, "#account_names-50")
    refute has_element?(view, "#account_names-51")
    assert has_element?(view, "#account-names-more[data-event=load_more_names][data-cursor]")

    render_hook(view, "load_more_names", %{})

    assert has_element?(view, "#account-names li:first-child strong", "name-1.regent.eth")

    assert has_element?(view, "#account-names li:last-child strong", "name-51.regent.eth")

    refute has_element?(view, "#account-names-more")

    # Nothing more to ask for leaves the list as it is.
    render_hook(view, "load_more_names", %{})
    assert has_element?(view, "#account_names-51")
    refute has_element?(view, "#account-names-more")
  end

  test "in-shell navigation keeps the LiveView and shell identity", %{conn: conn} do
    {:ok, view, html} = live(conn, "/app")
    pid = view.pid
    [instance] = Regex.run(~r/data-shell-instance="(\d+)"/, html, capture: :all_but_first)

    view
    |> element("#shell-sidebar a", "Stake")
    |> render_click()

    assert_patch(view, "/stake")
    assert view.pid == pid
    assert render(view) =~ ~s(data-shell-instance="#{instance}")
    assert has_element?(view, "#route-content h1", "Put REGENT to work.")
  end

  test "Formation remains owned by ShellLive with its background and only the handoff", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/formation")

    assert html =~ ~s(id="app-shell")
    assert html =~ ~s(id="app-shell-scroller")
    refute has_element?(view, ~s(.shell-background[data-background-slot="formation"]))
    assert has_element?(view, "#formation")

    assert has_element?(
             view,
             ~s(#formation-nous-portal-link[href="https://portal.nousresearch.com/cloud"][target="_blank"][rel="noopener noreferrer"]),
             "Open Nous Portal"
           )

    refute has_element?(view, "#formation form")
    refute has_element?(view, "#formation button")
    refute has_element?(view, "#formation [phx-click]")
    refute has_element?(view, "#formation [phx-submit]")
  end

  # /app shows the same shared contract reading every other page does, and an
  # anonymous visitor there buys no chain read either.
  test "anonymous /app paints the shared contract reading without reading Base", %{conn: conn} do
    seed_shared_snapshot()
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_read_watcher) end)

    {:ok, view, _html} = live(conn, "/app")

    assert has_element?(view, ".regent-ops-metric", "Total REGENT staked")
    assert render(view) =~ "100 REGENT"
    refute_received {:staking_read, _scope, _reader}

    # Nothing about any wallet is on screen for a visitor who has not signed in.
    refute has_element?(view, ".regent-ops-balances")
  end

  test "Account counts the claims the signed-in wallets may still make, and no one else's",
       %{conn: conn} do
    wallet = "0x9999999999999999999999999999999999999999"
    other = "0x9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a"
    stranger = "0x9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b"

    assert {:ok, account} =
             Accounts.register_verified("did:privy:account-claims", wallet, [wallet, other],
               actor: %System{}
             )

    insert_allowance(String.upcase(wallet), 5, 3)
    insert_allowance(other, 2, 2)
    insert_allowance(stranger, 9, 0)
    insert_payment_credit(1, other)
    insert_payment_credit(2, wallet, %{consumed_at: DateTime.utc_now()})
    insert_payment_credit(3, stranger)

    {view, _html} = open_account(conn, account)

    assert has_element?(view, "#account-claim-title", "Claim a Regent Name")
    assert has_element?(view, "#account-claims-available", "You can claim 2 more names free.")
    assert has_element?(view, "#account-claims-available", "You have 1 paid claim ready to use.")
    refute render(view) =~ "9 more"
    assert has_element?(view, "#account-claim-form input[name=name][value='']")
    assert has_element?(view, "#account-claim-availability[hidden]")
    assert has_element?(view, ".account-claim__later", "isn’t open yet")
  end

  test "Account tells a wallet with no free claims the price", %{conn: conn} do
    wallet = "0x9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c"
    account = register_account("account-no-claims", wallet)
    insert_allowance(wallet, 1, 1)

    {view, _html} = open_account(conn, account)

    assert has_element?(
             view,
             "#account-claims-available",
             "No free claims on your wallets. Names cost 0.0025 ETH each."
           )
  end

  test "Account judges a typed name by the rules and by the names already claimed", %{
    conn: conn
  } do
    wallet = "0x9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d"
    stranger = "0x9e9e9e9e9e9e9e9e9e9e9e9e9e9e9e9e9e9e9e9e"
    account = register_account("account-claim-name", wallet)
    insert_claim(1, stranger, %{label: "taken", fqdn: "taken.agent.base.eth"})

    {view, _html} = open_account(conn, account)

    render_change(element(view, "#account-claim-form"), %{"name" => "ab"})
    assert has_element?(view, "#account-claim-name-errors li", "Use at least 3 characters.")
    assert has_element?(view, "#account-claim-form input[aria-invalid=true][value=ab]")
    assert has_element?(view, "#account-claim-availability[hidden]")

    render_change(element(view, "#account-claim-form"), %{"name" => "-Bad.Name-too-long-"})
    html = render(view)
    assert html =~ "Use at most 14 characters."
    assert html =~ "Use only lowercase letters, numbers and hyphens."
    assert html =~ "A name can’t start or end with a hyphen."
    refute html =~ "Use at least 3 characters."

    render_change(element(view, "#account-claim-form"), %{"name" => "taken"})
    refute has_element?(view, "#account-claim-name-errors")
    assert has_element?(view, "#account-claim-availability", "taken is already claimed.")

    render_submit(element(view, "#account-claim-form"), %{"name" => "fresh-name-1"})

    assert has_element?(
             view,
             "#account-claim-availability",
             "fresh-name-1.regent.eth and fresh-name-1.agent.base.eth are available."
           )

    render_change(element(view, "#account-claim-form"), %{"name" => ""})
    assert has_element?(view, "#account-claim-availability[hidden]")
    refute has_element?(view, "#account-claim-name-errors")
    refute render(view) =~ "0x9e9e"
  end

  test "signed-in /app reads the account wallet at its own fresh block", %{conn: conn} do
    seed_shared_snapshot()
    account = register_account("app-wallet-read", "0x1111111111111111111111111111111111111111")

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    render_async(view)

    assert has_element?(view, ".regent-ops-balances", "Staked REGENT")
    assert render(view) =~ "5 REGENT"

    staking = :sys.get_state(view.pid).socket.assigns.staking

    assert staking.block_number == AshPlatform.TestStakingChainClient.protocol_block()
    assert staking.wallet_block_number == AshPlatform.TestStakingChainClient.wallet_block()
    assert staking.wallet_address == "0x1111111111111111111111111111111111111111"
  end

  test "malformed route parameters return not found", %{conn: conn} do
    assert_error_sent 404, fn ->
      get(conn, "/regents/not%20valid")
    end
  end

  defp seed_shared_snapshot do
    SnapshotCache.clear()
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())
    on_exit(&SnapshotCache.clear/0)
    assert :ok = SnapshotCache.refresh(self())
    assert_receive {:staking_snapshot, snapshot}
    snapshot
  end

  # Opening Account asks Ethereum about a wallet it has not read; the page is
  # only settled once that answer has landed.
  defp open_account(conn, account) do
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, AshPlatform.Ens.topic(account.id))

    {:ok, view, html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/account")

    assert_receive {:ens_lookup_finished, _account_id}, 2_000
    {view, html}
  end

  defp register_account(suffix, wallet) do
    assert {:ok, account} =
             Accounts.register_verified("did:privy:#{suffix}", wallet, [wallet], actor: %System{})

    account
  end

  defp render_shell(account_control) do
    route_spec = RouteCatalog.fetch!(:app, %{})

    render_component(&Shell.shell/1,
      route_spec: route_spec,
      account_control: account_control,
      shell_instance: 1,
      theme: "dark",
      content: [%{inner_block: fn _, _ -> "Fixture content" end}]
    )
  end
end
