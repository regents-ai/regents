defmodule AshPlatformWeb.PageControllerTest do
  use AshPlatformWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Regent"
    assert html =~ ~s(<meta name="privy-bridge-src" content="/assets/js/privy_bridge.js")
  end
end
