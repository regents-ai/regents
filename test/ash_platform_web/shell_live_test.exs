defmodule AshPlatformWeb.ShellLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.AccessContext.AccountControl
  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatformWeb.Components.Shell
  alias AshPlatformWeb.RouteCatalog
  alias AshPlatformWeb.ShellLive

  test "anonymous settings access redirects home without private content", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/settings")

    conn = get(conn, "/settings")
    assert redirected_to(conn) == "/"
    refute conn.resp_body =~ ~s(class="settings-page")
  end

  test "an anonymous shell cannot patch into settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")
    refute has_element?(view, "#route-content h1", "Settings")
    refute has_element?(view, "#route-content [aria-label=Appearance]")

    render_patch(view, "/settings")

    assert_redirect(view, "/")
  end

  test "an anonymous socket rejects a forged verified connection request", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")

    render_hook(view, "request_verified_connection", %{
      "action" => "link",
      "provider" => "x"
    })

    refute_push_event(view, "verified-connections:request", _payload)
  end

  test "direct deep links render the persistent shell and honest node state", %{conn: conn} do
    {:ok, view, html} =
      live(conn, "/techtree/nodes/00000000-0000-0000-0000-000000000001")

    assert html =~ ~s(id="app-shell")
    assert html =~ ~s(id="shell-header")
    assert html =~ ~s(id="shell-sidebar")
    assert html =~ ~s(id="app-shell-scroller")
    assert byte_size(html) <= 100 * 1024
    assert html =~ "Node not found"
    assert render_async(view) =~ "No public Techtree node exists"
  end

  test "anonymous account control renders Sign In separately from the app selector", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")

    assert has_element?(view, "#app-selector details")
    assert has_element?(view, "#app-selector summary", "Regents")
    assert has_element?(view, ~s(.shell-background[data-background-slot="regents_labs"]))
    assert has_element?(view, "#theme-control details")
    assert has_element?(view, "#account-control [data-account-target=sign-in]", "Sign In")

    assert has_element?(
             view,
             "#account-control #account-auth-status[role=status][aria-live=polite][aria-atomic=true][phx-update=ignore][hidden]"
           )

    refute has_element?(view, ".app-switcher [data-account-target=sign-in]")
    refute has_element?(view, "#account-control a", "Nous Portal")

    assert has_element?(view, "#app-selector nav a", "Autolaunch")
    refute has_element?(view, "#app-selector nav a", "Nous Portal")
    refute has_element?(view, "#app-selector nav a", "Techtree")
    refute has_element?(view, "#app-selector nav a", "Regents")
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

    assert has_element?(
             view,
             "#account-control button[data-account-copy-address]",
             "Copy address"
           )

    assert has_element?(
             view,
             ~s(#account-control[data-wallet-address="0x1111111111111111111111111111111111111111"])
           )

    refute has_element?(view, "#account-menu a", "Profile")
    refute has_element?(view, "#account-menu a", "Settings")
    refute has_element?(view, "#shell-header [data-theme-choice]")
    refute has_element?(view, "#account-control [phx-click]")
    refute has_element?(view, ".app-switcher [data-account-target]")
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
    refute has_element?(view, "#account-control [data-account-target=sign-out]", "Log Out")
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
    |> element("#shell-header a", "Techtree")
    |> render_click()

    assert_patch(view, "/techtree")
    assert view.pid == pid
    assert render(view) =~ ~s(data-shell-instance="#{instance}")
    assert has_element?(view, "#account-control [data-account-target=profile]", "0x2222…2222")
    assert has_element?(view, "#account-control [data-account-target=sign-out]", "Disconnect")
  end

  test "account dropdown omits profile and settings links while preserving its wallet controls" do
    html =
      render_shell(%AccountControl{
        kind: :signed_in,
        label: "Ada.regent.eth",
        profile_path: "/regents/ada",
        settings_path: "/settings",
        avatar_data_uri: "data:image/svg+xml;base64,PHN2Zy8+",
        wallet_address: "0x1111111111111111111111111111111111111111"
      })

    assert html =~ ~s(data-account-target="profile")
    assert html =~ ~s(class="account-avatar")
    assert html =~ ~s(src="data:image/svg+xml;base64,PHN2Zy8+")
    assert html =~ "Copy address"
    assert html =~ "Disconnect"

    [account_menu] =
      Regex.run(
        ~r/<details id="account-menu">(?<menu>.*?)<\/details>/s,
        html,
        capture: :all_names
      )

    refute account_menu =~ ~s(href="/regents/ada")
    refute account_menu =~ ~s(href="/settings")
    refute account_menu =~ ~r/>\s*Profile\s*<\/a>/
    refute account_menu =~ ~r/>\s*Settings\s*<\/a>/
    refute html =~ "Sign Out"
  end

  test "Settings owns an Appearance section rather than relabeling the whole page" do
    assert Code.ensure_loaded?(AshPlatformWeb.SettingsLive)
    assert function_exported?(AshPlatformWeb.SettingsLive, :page, 1)

    html = render_component(&AshPlatformWeb.SettingsLive.page/1, %{})

    assert html =~ ">Settings<"
    assert html =~ ">Appearance<"
    assert html =~ ~s(role="group")
    assert html =~ ~s(aria-label="Appearance")
    assert html =~ ~s(data-theme-choice="system")
    assert html =~ ~s(data-theme-choice="light")
    assert html =~ ~s(data-theme-choice="dark")
  end

  test "Settings shows live connected, disconnected, and conflict states", %{conn: conn} do
    account =
      register_account(
        "settings-connections",
        "0x6666666666666666666666666666666666666666"
      )

    actor = %AshPlatform.Actors.Human{human_account_id: account.id}

    x_attempt =
      Accounts.begin_x_connection_attempt!(
        %{
          role: :profile,
          attempt_state: "settings-state",
          attempt_verifier: "settings-verifier",
          attempt_generation: Ash.UUID.generate(),
          attempt_expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        },
        actor: actor
      )

    Accounts.complete_x_connection_attempt!(
      x_attempt,
      %{
        x_user_id: "settings-x-user",
        username: "settings_user",
        display_name: "Settings User",
        verified_at: DateTime.utc_now(),
        next_generation: Ash.UUID.generate()
      },
      actor: actor
    )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/settings")

    assert has_element?(
             view,
             ~s(#settings-x-connections-profile a[href="https://x.com/settings_user"]),
             "Settings User"
           )

    assert has_element?(view, "#settings-x-connections-profile button", "Disconnect")
    assert has_element?(view, "#settings-x-connections-company", "Optional · not connected")
    assert has_element?(view, "#settings-verified-connections-github", "Not connected")
    assert has_element?(view, "#settings-verified-connections-github button", "Connect")
    refute render(view) =~ "settings-x-user"

    render_hook(view, "refresh_verified_connections", %{"error" => "already-connected"})

    assert has_element?(
             view,
             "#settings-verified-connections [role=alert]",
             "already connected to another Regent account"
           )
  end

  test "in-shell navigation keeps the LiveView and shell identity", %{conn: conn} do
    {:ok, view, html} = live(conn, "/app")
    pid = view.pid
    [instance] = Regex.run(~r/data-shell-instance="(\d+)"/, html, capture: :all_but_first)

    view
    |> element("#shell-header a", "Techtree")
    |> render_click()

    assert_patch(view, "/techtree")
    assert view.pid == pid
    assert render(view) =~ ~s(data-shell-instance="#{instance}")
    assert has_element?(view, "#route-content h1", "Techtree")
  end

  test "same-tree Map and List controls are local buttons rather than navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/techtree/genebench-pro-reference-lab")
    render_async(view)

    assert has_element?(
             view,
             ~s(a[data-tree-presentation="map"][data-tree-path="/techtree/genebench-pro-reference-lab"][aria-pressed="true"])
           )

    assert has_element?(
             view,
             ~s(a[data-tree-presentation="list"][data-tree-path="/techtree/genebench-pro-reference-lab"][aria-pressed="false"])
           )

    assert has_element?(
             view,
             ~s(a[data-tree-presentation][href="/techtree/genebench-pro-reference-lab"])
           )

    refute has_element?(view, ~s([data-tree-presentation][phx-click]))
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
    |> element("#shell-header a", "Techtree")
    |> render_click()

    assert_patch(view, "/techtree")
    assert_receive {:DOWN, ^monitor, :process, ^task_pid, _reason}
    html = render_async(view)
    assert html =~ "Research with Techtree"
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

  test "malformed and reserved route parameters return not found", %{conn: conn} do
    assert_error_sent(404, fn -> get(conn, "/techtree/nodes") end)
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
      app_targets: RouteCatalog.app_targets(),
      account_control: account_control,
      content_status: :ready,
      presentation: :none,
      shell_instance: 1,
      content: [%{inner_block: fn _, _ -> "Fixture content" end}]
    )
  end
end
