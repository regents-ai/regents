defmodule AshPlatformWeb.MetricsController do
  use AshPlatformWeb, :controller

  def show(conn, _params) do
    body =
      TelemetryMetricsPrometheus.Core.scrape(AshPlatformWeb.Telemetry.prometheus_reporter())

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(:ok, body)
  end
end
