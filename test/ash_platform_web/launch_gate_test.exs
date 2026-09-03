defmodule AshPlatformWeb.LaunchGateTest do
  use AshPlatformWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.{Accounts, Autolaunch, Formation}
  alias AshPlatform.Actors.Human
  alias AshPlatformWeb.Live.LaunchGateHook
  alias AshPlatformWeb.Plugs.LaunchGate

  # Settings returns soon (founder, 2026-09-03): switched off, not removed. (/settings left out of the gated paths)
  @gated_shell_paths ~w(/app /formation /regents/example /techtree /autolaunch /stake /redeem)
  @autolaunch_paths ~w(/autolaunch /autolaunch/auctions /autolaunch/holdings /autolaunch/create)
  @closed_message "This part of Regent isn't open yet."
  @draft_fields %{
    "name" => "Injected Launch",
    "symbol" => "INJECT",
    "description" => "An injected draft that must never be recorded.",
    "website" => "https://example.test/injected",
    "image" => "https://example.test/injected.png",
    "treasury" => "0xAbCdeF0000000000000000000000000000000001",
    "required_regent_raised" => "1000.5"
  }
  @kept_draft %{@draft_fields | "name" => "Kept Launch", "symbol" => "KEPT"}

  setup do
    on_exit(fn ->
      open_surfaces()
      open_autolaunch()
    end)

    :ok
  end

  defp close_surfaces, do: Application.put_env(:ash_platform, :app_surfaces, false)
  defp open_surfaces, do: Application.put_env(:ash_platform, :app_surfaces, true)
  defp close_autolaunch, do: Application.put_env(:ash_platform, :autolaunch_surfaces, false)
  defp open_autolaunch, do: Application.put_env(:ash_platform, :autolaunch_surfaces, true)

  test "[U1] one switch is open by default and reads both explicit states" do
    Application.delete_env(:ash_platform, :app_surfaces)
    assert LaunchGate.app_surfaces_enabled?()

    open_surfaces()
    assert LaunchGate.app_surfaces_enabled?()

    close_surfaces()
    refute LaunchGate.app_surfaces_enabled?()
  end

  test "[U1] the switch takes effect between requests of one running build" do
    assert get(build_conn(), "/app").status == 200

    close_surfaces()
    assert get(build_conn(), "/app").status == 503

    open_surfaces()
    assert get(build_conn(), "/app").status == 200
  end

  test "[U1] production refuses to boot without an explicit setting, and records the state" do
    original = System.get_env("ASH_PLATFORM_APP_SURFACES")
    on_exit(fn -> restore_setting(original) end)
    System.delete_env("ASH_PLATFORM_APP_SURFACES")

    assert_raise RuntimeError, ~s(ASH_PLATFORM_APP_SURFACES must be set to "on" or "off"), fn ->
      read_runtime_config(:prod)
    end

    assert {config, log} = read_runtime_config(:test)
    assert config[:ash_platform][:app_surfaces]
    assert log =~ "App surfaces enabled"

    System.put_env("ASH_PLATFORM_APP_SURFACES", "yes")

    assert {config, log} = read_runtime_config(:test)
    refute config[:ash_platform][:app_surfaces]
    assert log =~ "App surfaces disabled"
  end

  test "[U2] every product route answers 503 with no product markup and no caching" do
    close_surfaces()

    for path <- @gated_shell_paths do
      conn = get(build_conn(), path)

      assert conn.status == 503, "#{path} stayed open"
      assert get_resp_header(conn, "retry-after") == ["3600"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      refute conn.resp_body =~ ~s(id="app-shell")
    end
  end

  test "[U2] gated pages and JSON answers carry the same browser security headers as an open page" do
    open = get(build_conn(), "/app")
    close_surfaces()

    assert secure_headers(get(build_conn(), "/app")) == secure_headers(open)
    assert secure_headers(get(build_conn(), "/api/techtree/v1/trees")) == secure_headers(open)
    assert secure_headers(open) != %{}
  end

  test "[U2] read, session and agent-write JSON endpoints answer one plain 503 line" do
    close_surfaces()

    for conn <- [
          get(build_conn(), "/api/techtree/v1/trees"),
          get(build_conn(), "/api/formation/v1/regents/1/agent-links"),
          post(build_conn(), "/api/techtree/v1/nodes", %{}),
          get(build_conn(), "/auth/session")
        ] do
      assert json_response(conn, 503) == %{"error" => @closed_message}
      assert get_resp_header(conn, "retry-after") == ["3600"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  test "[U2] the gate answers agent writes before agent authentication runs" do
    assert json_response(publish_as_signed_in_person(), 401)

    close_surfaces()
    assert json_response(publish_as_signed_in_person(), 503) == %{"error" => @closed_message}
  end

  test "[U3] the marketing page, health check and static files are untouched by the gate" do
    close_surfaces()
    home = get(build_conn(), "/")

    title =
      home.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("h1#home-title")
      |> LazyHTML.text()
      |> String.trim()

    assert home.status == 200
    assert title == "Regents Labs"
    refute home.resp_body =~ "Not open yet"

    assert get(build_conn(), "/healthz").status == 200
    assert get(build_conn(), "/healthz").resp_body == "ok"
    assert get(build_conn(), "/robots.txt").status == 200
  end

  test "[U2] signing out stays available while every other session endpoint closes" do
    close_surfaces()

    assert json_response(delete(build_conn(), "/auth/privy/session"), 200) == %{"ok" => true}
    assert json_response(get(build_conn(), "/auth/csrf"), 503) == %{"error" => @closed_message}

    assert json_response(post(build_conn(), "/auth/privy/session", %{}), 503) ==
             %{"error" => @closed_message}
  end

  test "[U2] a mount arriving over the socket is sent to the marketing page instead" do
    close_surfaces()

    assert {:halt, halted} =
             LaunchGateHook.on_mount(:default, %{}, %{}, %Phoenix.LiveView.Socket{})

    assert halted.redirected == {:redirect, %{to: "/", status: 302}}
  end

  test "[U2] a page open when the gate closes cannot keep browsing product routes", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")

    close_surfaces()
    render_patch(view, "/techtree")

    assert_redirect(view, "/")
  end

  test "[U4] the Autolaunch switch is closed when unset and reads both explicit states" do
    Application.delete_env(:ash_platform, :autolaunch_surfaces)
    refute LaunchGate.autolaunch_surfaces_enabled?()

    open_autolaunch()
    assert LaunchGate.autolaunch_surfaces_enabled?()

    close_autolaunch()
    refute LaunchGate.autolaunch_surfaces_enabled?()
  end

  test "[U4] Autolaunch pages and endpoints close while every other surface stays open" do
    close_autolaunch()

    for path <- @autolaunch_paths do
      conn = get(build_conn(), path)

      assert conn.status == 503, "#{path} stayed open"
      assert get_resp_header(conn, "retry-after") == ["3600"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      refute conn.resp_body =~ ~s(id="app-shell")
    end

    assert json_response(get(build_conn(), "/api/autolaunch/v1/auctions"), 503) ==
             %{"error" => @closed_message}

    for path <- ~w(/ /app /stake /redeem /techtree) do
      assert get(build_conn(), path).status == 200, "#{path} closed with Autolaunch"
    end

    assert get(build_conn(), "/auth/csrf").status == 200
    assert get(build_conn(), "/api/techtree/v1/trees").status == 200
  end

  test "[U4] an Autolaunch mount arriving over the socket is sent to the application home" do
    close_autolaunch()

    assert {:halt, halted} =
             LaunchGateHook.on_mount(:default, %{}, %{}, autolaunch_socket())

    assert halted.redirected == {:redirect, %{to: "/app", status: 302}}
  end

  test "[U4] a page open when Autolaunch closes cannot navigate into it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")

    close_autolaunch()
    render_patch(view, "/autolaunch/create")

    assert_redirect(view, "/app")
  end

  test "[U4] injected draft events from Stake record nothing while Autolaunch is closed", %{
    conn: conn
  } do
    account =
      Accounts.register_verified!(
        "did:privy:launch-gate-draft",
        "0x4444444444444444444444444444444444444444",
        ["0x4444444444444444444444444444444444444444"],
        actor: %AshPlatform.Actors.System{}
      )

    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("gate-regent", "Gate Regent", actor: actor)

    {:ok, draft} = Autolaunch.create_launch_draft(@kept_draft, actor: actor)

    close_autolaunch()

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_hook(view, "create_launch_draft", %{"launch_draft" => @draft_fields})

    render_hook(view, "revise_launch_draft", %{
      "draft_id" => to_string(draft.id),
      "launch_draft" => @draft_fields
    })

    assert {:ok, [persisted]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert {persisted.id, persisted.name, persisted.symbol} == {draft.id, "Kept Launch", "KEPT"}

    assigns = :sys.get_state(view.pid).socket.assigns
    assert assigns.autolaunch_launch_drafts == []
    assert assigns.autolaunch_draft_notice == %{tone: :error, message: @closed_message}
  end

  defp autolaunch_socket,
    do: Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, :live_action, :autolaunch_create)

  # Reads the file a boot reads, returning its settings and the log it wrote.
  defp read_runtime_config(env) do
    level = Logger.level()
    Logger.configure(level: :info)

    try do
      with_log(fn -> Config.Reader.read!("config/runtime.exs", env: env) end)
    after
      Logger.configure(level: level)
    end
  end

  defp restore_setting(nil), do: System.delete_env("ASH_PLATFORM_APP_SURFACES")
  defp restore_setting(setting), do: System.put_env("ASH_PLATFORM_APP_SURFACES", setting)

  defp publish_as_signed_in_person do
    build_conn()
    |> put_req_header("authorization", "Bearer privy-token")
    |> post("/api/techtree/v1/nodes", %{})
  end

  defp secure_headers(conn) do
    conn.resp_headers
    |> Map.new()
    |> Map.take(~w(content-security-policy referrer-policy x-content-type-options
       x-permitted-cross-domain-policies x-frame-options))
  end
end
