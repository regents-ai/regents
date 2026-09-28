defmodule RegentsWeb.LaunchGateTest do
  use RegentsWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias RegentsWeb.Live.LaunchGateHook
  alias RegentsWeb.Plugs.LaunchGate

  # Settings returns soon (founder, 2026-09-03): switched off, not removed. (/settings left out of the gated paths)
  @gated_shell_paths ~w(/app /regents/example /stake /redeem)
  @closed %{
    "error" => %{
      "code" => "not_open_yet",
      "message" => "This part of Regent isn't open yet.",
      "hint" => "Ask again after the number of seconds in Retry-After."
    }
  }

  setup do
    on_exit(&open_surfaces/0)

    :ok
  end

  defp close_surfaces, do: Application.put_env(:regents, :app_surfaces, false)
  defp open_surfaces, do: Application.put_env(:regents, :app_surfaces, true)

  test "[U1] one switch reads both explicit states" do
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
    original = System.get_env("REGENTS_APP_SURFACES")
    on_exit(fn -> restore_setting(original) end)
    System.delete_env("REGENTS_APP_SURFACES")

    assert_raise RuntimeError, ~s(REGENTS_APP_SURFACES must be set to "on" or "off"), fn ->
      read_runtime_config(:prod)
    end

    assert {config, log} = read_runtime_config(:test)
    assert config[:regents][:app_surfaces]
    assert log =~ "App surfaces enabled"

    System.put_env("REGENTS_APP_SURFACES", "yes")

    assert {config, log} = read_runtime_config(:test)
    refute config[:regents][:app_surfaces]
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

    assert secure_headers(get(build_conn(), "/auth/session")) == secure_headers(open)

    assert secure_headers(open) != %{}
  end

  test "[U2] session and agent JSON endpoints answer one plain 503 line" do
    close_surfaces()

    for conn <- [
          get(build_conn(), "/api/agents/v1/me"),
          post(build_conn(), "/api/agents/v1/pair", %{}),
          get(build_conn(), "/auth/session")
        ] do
      assert json_response(conn, 503) == @closed
      assert get_resp_header(conn, "retry-after") == ["3600"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  test "[U2] the gate answers agent writes before pairing runs" do
    assert json_response(pair_request(), 400) == %{
             "error" => %{
               "code" => "pairing_failed",
               "message" => "The pairing code could not be used.",
               "hint" =>
                 "Ask your person for a new pairing code. Each code works once and expires ten minutes after it was made."
             }
           }

    close_surfaces()
    assert json_response(pair_request(), 503) == @closed
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
    assert get(build_conn(), "/privacy").status == 200
    assert get(build_conn(), "/terms").status == 200
  end

  test "[U2] signing out stays available while every other session endpoint closes" do
    close_surfaces()

    assert json_response(delete(build_conn(), "/auth/privy/session"), 200) == %{"ok" => true}
    assert json_response(get(build_conn(), "/auth/csrf"), 503) == @closed

    assert json_response(post(build_conn(), "/auth/privy/session", %{}), 503) ==
             @closed
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
    render_patch(view, "/stake")

    assert_redirect(view, "/")
  end

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

  defp restore_setting(nil), do: System.delete_env("REGENTS_APP_SURFACES")
  defp restore_setting(setting), do: System.put_env("REGENTS_APP_SURFACES", setting)

  defp pair_request, do: post(build_conn(), "/api/agents/v1/pair", %{})

  defp secure_headers(conn) do
    conn.resp_headers
    |> Map.new()
    |> Map.take(~w(content-security-policy referrer-policy x-content-type-options
       x-permitted-cross-domain-policies x-frame-options))
  end
end
