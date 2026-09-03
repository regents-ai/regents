defmodule AshPlatformWeb.ShellLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.AccessContext.AccountControl
  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatformWeb.Components.Shell
  alias AshPlatformWeb.RouteCatalog
  alias AshPlatformWeb.ShellLive

  # Settings returns soon (founder, 2026-09-03): switched off, not removed.
  # test "anonymous settings access redirects home without private content", %{conn: conn} do
  #   assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/settings")

  #   conn = get(conn, "/settings")
  #   assert redirected_to(conn) == "/"
  #   refute conn.resp_body =~ ~s(class="settings-page")
  # end

  # Settings returns soon (founder, 2026-09-03): switched off, not removed.
  # test "an anonymous shell cannot patch into settings", %{conn: conn} do
  #   {:ok, view, _html} = live(conn, "/app")
  #   refute has_element?(view, "#route-content h1", "Settings")
  #   refute has_element?(view, "#route-content .verified-connections")

  #   render_patch(view, "/settings")

  #   assert_redirect(view, "/")
  # end

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
    assert has_element?(view, ~s(.shell-background[data-background-slot="regents_labs"]))
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
    # Settings returns soon (founder, 2026-09-03): switched off, not removed.
    # assert has_element?(view, "#account-control a[data-account-menu-item=settings]", "Settings")
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
        settings_path: "/settings",
        avatar_src: "data:image/svg+xml;base64,PHN2Zy8+"
      })

    assert html =~ ~s(data-account-target="profile")
    assert html =~ ~s(href="/regents/ada")
    assert html =~ ~r/>\s*Profile\s*<\/a>/
    assert html =~ ~s(class="account-avatar")
    assert html =~ ~s(src="data:image/svg+xml;base64,PHN2Zy8+")
    # Settings returns soon (founder, 2026-09-03): switched off, not removed.
    # assert html =~ ~s(href="/settings")
    # assert html =~ ~s(data-account-menu-item="settings")
    # assert html =~ ~r/>\s*Settings\s*<\/span>/
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
    assert AshPlatform.Ens.refresh(account) == :ok
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
        settings_path: "/settings",
        avatar_src: "https://avatars.regents.test/atlas.png"
      })

    assert html =~ ~s(src="https://avatars.regents.test/atlas.png")
    assert html =~ ~r/data-account-target="profile">\s*atlas.eth\s*</
  end

  test "Settings owns its own page rather than relabeling the whole shell" do
    assert Code.ensure_loaded?(AshPlatformWeb.SettingsLive)
    assert function_exported?(AshPlatformWeb.SettingsLive, :page, 1)

    html = render_component(&AshPlatformWeb.SettingsLive.page/1, %{})

    assert html =~ ">Settings<"
    assert html =~ ~s(id="settings-verified-connections")
    assert html =~ ">Verified connections<"
  end

  # Settings returns soon (founder, 2026-09-03): switched off, not removed.
  # test "Settings shows live connected, disconnected, and conflict states", %{conn: conn} do
  #   account =
  #     register_account(
  #       "settings-connections",
  #       "0x6666666666666666666666666666666666666666"
  #     )

  #   Accounts.upsert_linked_identity!(
  #     :x,
  #     "settings-x-subject",
  #     "settings_user",
  #     "Settings User",
  #     DateTime.utc_now(),
  #     %{},
  #     account.id,
  #     actor: %System{}
  #   )

  #   {:ok, view, _html} =
  #     conn
  #     |> init_test_session(%{human_account_id: account.id})
  #     |> live("/settings")

  #   assert has_element?(
  #            view,
  #            ~s(#settings-verified-connections-x a[href="https://x.com/settings_user"]),
  #            "@settings_user"
  #          )

  #   assert has_element?(view, "#settings-verified-connections-x button", "Disconnect")
  #   assert has_element?(view, "#settings-verified-connections-github", "Not connected")
  #   assert has_element?(view, "#settings-verified-connections-github button", "Connect")
  #   refute render(view) =~ "settings-x-subject"

  #   view
  #   |> element("#settings-verified-connections-x button", "Disconnect")
  #   |> render_click()

  #   assert_push_event(view, "verified-connections:request", %{
  #     action: :unlink,
  #     provider: :x,
  #     subject: "settings-x-subject"
  #   })

  #   render_hook(view, "refresh_verified_connections", %{"error" => "already-connected"})

  #   assert has_element?(
  #            view,
  #            "#settings-verified-connections [role=alert]",
  #            "already connected to another Regent account"
  #          )
  # end

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
    assert has_element?(view, ~s(.shell-background[data-background-slot="formation"]))
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

  test "a newer destination cancels blocked scaffold work and becomes the only content", %{
    conn: conn
  } do
    Process.register(self(), AshPlatform.ContentFixtureObserver)

    {:ok, view, html} = live(conn, "/regents/fixture-blocked")
    assert html =~ "Regent not found"
    assert_receive {:fixture_content_started, task_pid}
    monitor = Process.monitor(task_pid)

    view
    |> element("#shell-sidebar a", "Stake")
    |> render_click()

    assert_patch(view, "/stake")
    assert_receive {:DOWN, ^monitor, :process, ^task_pid, _reason}
    html = render_async(view)
    assert html =~ "Put REGENT to work."
    refute html =~ "Stale fixture"
  end

  test "stale async successes and exits cannot replace the active destination" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        content_generation: 2,
        content_status: :ready,
        content: :current
      }
    }

    assert {:noreply, unchanged} =
             ShellLive.handle_async({:content, 1}, {:ok, {1, {:ok, :stale}}}, socket)

    assert unchanged.assigns.content == :current
    assert unchanged.assigns.content_status == :ready

    assert {:noreply, unchanged} =
             ShellLive.handle_async({:content, 1}, {:exit, :stale_crash}, socket)

    assert unchanged.assigns.content == :current
    assert unchanged.assigns.content_status == :ready
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
    auction_id = String.duplicate("a", 129)

    assert_error_sent 404, fn ->
      get(conn, "/autolaunch/auctions/#{auction_id}")
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
      content_status: :ready,
      shell_instance: 1,
      theme: "dark",
      content: [%{inner_block: fn _, _ -> "Fixture content" end}]
    )
  end
end
