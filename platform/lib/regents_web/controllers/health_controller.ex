defmodule RegentsWeb.HealthController do
  @moduledoc """
  Whether the site and its own database answer: `/healthz` in plain text for the
  host's health check, `/api/v1/health` in JSON for the command line. The JSON
  also says whether this release's migrations are all applied; pending ones
  leave the answer at 200, so the host does not restart a site that is serving.
  """
  use RegentsWeb, :controller

  alias Regents.Health

  def show(conn, _params) do
    {status, body} =
      if Health.database_ready?(), do: {:ok, "ok"}, else: {:service_unavailable, "unavailable"}

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end

  def status(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    if Health.database_ready?() do
      json(conn, %{status: "ok", migrations_applied: Health.migrations_applied?()})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{
        error: %{
          code: "unavailable",
          message: "The site is up but its database is not answering.",
          hint: "Try again in a minute."
        }
      })
    end
  end
end
