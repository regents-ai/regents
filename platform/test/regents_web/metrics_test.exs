defmodule RegentsWeb.MetricsTest do
  use RegentsWeb.ConnCase, async: false

  alias RegentsWeb.Metrics

  test "PRIVATE_SCRAPE: the metrics listener serves the bounded Privy browser failure counter" do
    :telemetry.execute([:regents, :privy, :browser_failure], %{count: 1}, %{
      reason: "provider_error"
    })

    conn = Metrics.call(Plug.Test.conn(:get, "/metrics"), [])

    assert conn.status == 200
    assert conn.resp_body =~ ~s(regents_privy_browser_failure_total{reason="provider_error"})
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end

  test "the metrics listener answers nothing else" do
    assert Metrics.call(Plug.Test.conn(:get, "/healthz"), []).status == 404
    assert Metrics.call(Plug.Test.conn(:post, "/metrics"), []).status == 404
  end

  test "PUBLIC_SITE: the public site never serves metrics, and health stays open", %{conn: conn} do
    assert conn |> get("/metrics") |> response(404)
    assert conn |> get("/healthz") |> response(200)
  end
end
