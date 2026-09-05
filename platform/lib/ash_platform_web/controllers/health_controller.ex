defmodule AshPlatformWeb.HealthController do
  use AshPlatformWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(:ok, "ok")
  end
end
