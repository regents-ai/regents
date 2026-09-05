defmodule AshPlatformWeb.HealthControllerTest do
  use AshPlatformWeb.ConnCase, async: true

  test "PKG-HEALTH public GET /healthz returns only plain-text liveness", %{conn: conn} do
    response = get(conn, "/healthz")

    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["text/plain; charset=utf-8"]
    assert response.resp_body == "ok"
  end
end
