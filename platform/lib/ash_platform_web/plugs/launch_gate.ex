defmodule AshPlatformWeb.Plugs.LaunchGate do
  @moduledoc """
  Closes every non-marketing surface while the launch gate is closed.

  The setting is read on each request, so a deploy opens or closes surfaces
  without rebuilding the release. The marketing page and signing out stay open
  in either state. The Privacy Policy and Terms of Use stay open with them.
  """

  import Phoenix.Controller, only: [get_format: 1, json: 2, put_secure_browser_headers: 1]
  import Plug.Conn

  alias AshPlatformWeb.HoldingController

  @doc "True while the product surfaces are open."
  def app_surfaces_enabled?, do: Application.fetch_env!(:ash_platform, :app_surfaces)

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", path_info: []} = conn, _opts), do: conn

  def call(%Plug.Conn{method: "GET", path_info: ["privacy"]} = conn, _opts), do: conn

  def call(%Plug.Conn{method: "GET", path_info: ["terms"]} = conn, _opts), do: conn

  def call(%Plug.Conn{method: "GET", path_info: ["blog"]} = conn, _opts), do: conn
  def call(%Plug.Conn{method: "GET", path_info: ["blog", _slug]} = conn, _opts), do: conn

  def call(%Plug.Conn{method: "DELETE", path_info: ["auth", "privy", "session"]} = conn, _opts),
    do: conn

  def call(conn, _opts), do: gate(app_surfaces_enabled?(), conn)

  defp gate(true, conn), do: conn
  defp gate(false, conn), do: conn |> closed(response_format(conn)) |> halt()

  # The session endpoints ride the browser pipeline but answer JSON callers.
  defp response_format(%Plug.Conn{path_info: ["auth" | _]}), do: "json"
  defp response_format(conn), do: get_format(conn)

  defp closed(conn, "json"),
    do:
      conn
      |> put_secure_browser_headers()
      |> unavailable()
      |> json(%{error: "This part of Regent isn't open yet."})

  defp closed(conn, "html"),
    do: conn |> put_secure_browser_headers() |> unavailable() |> HoldingController.call(:show)

  defp unavailable(conn) do
    conn
    |> put_status(:service_unavailable)
    |> put_resp_header("retry-after", "3600")
    |> put_resp_header("cache-control", "no-store")
  end
end
