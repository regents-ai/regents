defmodule RegentsWeb.CutoverRedirectController do
  @moduledoc false
  use RegentsWeb, :controller

  def mcp_read(conn, _params), do: permanent(conn, "/mcp")
  def mcp_write(conn, _params), do: permanent(conn, "/mcp")
  def robots(conn, _params), do: permanent(conn, "/robots.txt")
  def sitemap(conn, _params), do: permanent(conn, "/sitemap.xml")

  defp permanent(conn, path) do
    location = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

    conn
    |> put_resp_header("location", location)
    |> send_resp(308, "")
  end
end
