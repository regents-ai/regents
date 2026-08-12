defmodule AshPlatformWeb.LaunchGateTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatformWeb.Live.LaunchGateHook
  alias AshPlatformWeb.Plugs.LaunchGate

  @gated_shell_paths ~w(/app /settings /formation /regents/example /techtree /autolaunch /stake /redeem)
  @closed_message "This part of Regent isn't open yet."

  setup do
    on_exit(fn -> open_surfaces() end)
    :ok
  end

  defp close_surfaces, do: Application.put_env(:ash_platform, :app_surfaces, false)
  defp open_surfaces, do: Application.put_env(:ash_platform, :app_surfaces, true)

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

  test "[U2] the gated page carries the same browser security headers as an open page" do
    open = get(build_conn(), "/app")
    close_surfaces()
    gated = get(build_conn(), "/app")

    assert secure_headers(gated) == secure_headers(open)
    assert secure_headers(gated) != %{}
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

    assert home.status == 200
    assert home.resp_body =~ "Build agents that can own their work."
    refute home.resp_body =~ "Not open yet"

    assert get(build_conn(), "/healthz").status == 200
    assert get(build_conn(), "/healthz").resp_body == "ok"
    assert get(build_conn(), "/robots.txt").status == 200
  end

  test "[U2] signing out stays available while every other session endpoint closes" do
    close_surfaces()

    assert json_response(delete(build_conn(), "/auth/privy/session"), 200) == %{"ok" => true}
    assert json_response(get(build_conn(), "/auth/csrf"), 503) == %{"error" => @closed_message}
    assert json_response(post(build_conn(), "/auth/privy/session", %{}), 503)
  end

  test "[U2] a mount arriving over the socket is sent to the marketing page instead" do
    socket = %Phoenix.LiveView.Socket{}

    assert {:cont, ^socket} = LaunchGateHook.on_mount(:default, %{}, %{}, socket)

    close_surfaces()

    assert {:halt, halted} = LaunchGateHook.on_mount(:default, %{}, %{}, socket)
    assert halted.redirected == {:redirect, %{to: "/", status: 302}}
  end

  test "[U2] the product shell live session mounts through the gate first" do
    %{phoenix_live_view: {AshPlatformWeb.ShellLive, _action, _opts, %{extra: %{on_mount: hooks}}}} =
      Phoenix.Router.route_info(AshPlatformWeb.Router, "GET", "/app", "127.0.0.1")

    assert [%{id: {LaunchGateHook, :default}, stage: :mount} | _rest] = hooks
  end

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
