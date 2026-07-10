defmodule AshPlatformWeb.PageControllerTest do
  use AshPlatformWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Regent"
  end
end
