defmodule RegentsWeb.PublicResponse do
  @moduledoc "Cacheable public bytes and conditional GETs."

  import Plug.Conn

  @doc "Sends a release document with a tag for the exact bytes."
  # Public document callers choose the media type and supply authored release bytes.
  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  def send_cached(conn, type, body, charset \\ "utf-8") do
    etag = ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}")

    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "public, max-age=300")

    if holds?(conn, etag) do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type(type, charset)
      |> send_resp(200, body)
    end
  end

  @doc "Whether the request carries a matching entity tag, using weak comparison."
  def holds?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&Plug.Conn.Utils.list/1)
    |> Enum.any?(&(&1 == "*" or String.replace_prefix(&1, "W/", "") == etag))
  end
end
