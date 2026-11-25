defmodule RegentsWeb.Plugs.LaunchGate do
  @moduledoc """
  Closes every non-marketing surface while the launch gate is closed.

  The setting is read on each request, so a deploy opens or closes surfaces
  without rebuilding the release. The marketing page and signing out stay open
  in either state. The Privacy Policy, Terms of Use, Articles, Paper Pro Daily and
  the agent start page stay open with them, along with the public docs.
  """

  import Phoenix.Controller, only: [get_format: 1, json: 2, put_secure_browser_headers: 2]
  import Plug.Conn

  alias RegentsWeb.{ContentSecurityPolicy, HoldingController}

  # A closed answer carries the same browser headers as the open page it stands in for.
  defp browser_headers, do: %{"content-security-policy" => ContentSecurityPolicy.sign_in()}

  @doc "True while the product surfaces are open."
  def app_surfaces_enabled?, do: Application.fetch_env!(:regents, :app_surfaces)

  def init(opts), do: opts

  @doc "Whether a public document can be rendered before the router."
  def document(path) do
    if app_surfaces_enabled?() or public_read?(String.split(path, "/", trim: true)) do
      RegentsWeb.PublicDocuments.document(path)
    end
  end

  def call(%Plug.Conn{method: method, path_info: path} = conn, _opts)
      when method in ["GET", "HEAD"] do
    if public_read?(path), do: conn, else: gate(app_surfaces_enabled?(), conn)
  end

  def call(%Plug.Conn{method: "POST", path_info: ["visit-log"]} = conn, _opts), do: conn

  def call(%Plug.Conn{method: "DELETE", path_info: ["auth", "privy", "session"]} = conn, _opts),
    do: conn

  def call(conn, _opts), do: gate(app_surfaces_enabled?(), conn)

  defp public_read?([]), do: true

  defp public_read?([page])
       when page in ~w(privacy terms articles blog literature about agents changelog start paper-pro-daily cloak siwa autolaunch keyfleet patchbay techtree),
       do: true

  defp public_read?([collection, _entry])
       when collection in ~w(articles blog paper-pro-daily agents),
       do: true

  defp public_read?(["docs" | _]), do: true
  defp public_read?(["cloak", "install"]), do: true
  defp public_read?(["auth", "csrf"]), do: true
  defp public_read?(["api", "v1", resource]) when resource in ~w(health docs site-tools), do: true
  defp public_read?(["api", "v1", "site-tools", _site]), do: true

  defp public_read?(["api", "v1", "reading", collection]),
    do: collection in ~w(papers articles literature)

  defp public_read?(["api", "v1", "reading", collection, _id]),
    do: collection in ~w(papers articles)

  defp public_read?(_path), do: false

  defp gate(true, conn), do: conn
  defp gate(false, conn), do: conn |> closed(response_format(conn)) |> halt()

  # The session endpoints ride the browser pipeline but answer JSON callers.
  defp response_format(%Plug.Conn{path_info: ["auth" | _]}), do: "json"
  defp response_format(conn), do: get_format(conn) || "html"

  defp closed(conn, "json") do
    conn
    |> put_secure_browser_headers(browser_headers())
    |> unavailable()
    |> json(%{
      error: %{
        code: "not_open_yet",
        message: "This part of Regent isn't open yet.",
        hint: "Ask again after the number of seconds in Retry-After."
      }
    })
  end

  defp closed(conn, "html"),
    do:
      conn
      |> put_secure_browser_headers(browser_headers())
      |> unavailable()
      |> HoldingController.call(:show)

  # The holding page's words, for a page that also answers Markdown (Patchbay's).
  defp closed(conn, "md"),
    do:
      conn
      |> put_secure_browser_headers(browser_headers())
      |> unavailable()
      |> put_resp_content_type("text/markdown")
      |> send_resp(
        :service_unavailable,
        "# Not open yet\n\nThis part of Regent isn't open to visitors yet. " <>
          "Everything we have shown so far is on the homepage: [/](/).\n"
      )

  defp unavailable(conn) do
    conn
    |> put_status(:service_unavailable)
    |> put_resp_header("retry-after", "3600")
    |> put_resp_header("cache-control", "no-store")
  end
end
