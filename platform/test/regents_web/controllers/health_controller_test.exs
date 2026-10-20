defmodule RegentsWeb.HealthControllerTest do
  use RegentsWeb.ConnCase, async: true

  test "PKG-HEALTH /healthz says ok only after reading the site's own table", %{conn: conn} do
    response = get(conn, "/healthz")

    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert response.resp_body == "ok"
  end

  test "/api/v1/health answers the same check in JSON", %{conn: conn} do
    response = get(conn, "/api/v1/health")

    assert json_response(response, 200) == %{"status" => "ok"}
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end
end
