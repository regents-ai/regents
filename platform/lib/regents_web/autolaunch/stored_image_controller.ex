defmodule RegentsWeb.Autolaunch.StoredImageController do
  @moduledoc """
  The launch pictures autolaunch.sh stored (`Regents.Autolaunch.StoredImage`),
  for anyone: a Revstake draft's at `/autolaunch/images/<id>/<digest>` and a
  Memestock draft's at `/autolaunch/stock-images/<id>/<digest>`, as stored, and
  each one's sized copies at `<address>/<width>.webp`. The id and the full
  digest together name a picture, and its bytes never change under them, so a
  browser may keep what it got for good. Anything else answers 404.

  Opened on its own, a picture may do nothing, as the site's static files may;
  the endpoint's headers say the rest (`nosniff` among them).
  """
  use RegentsWeb, :controller

  alias Regents.Autolaunch.StoredImage

  # The three types a stored picture may have; the bytes are sent as the one
  # stored, never as what they look like.
  @types ["image/png", "image/jpeg", "image/webp"]
  @alone %{
    "content-security-policy" => "default-src 'none'; frame-ancestors 'none'",
    "x-frame-options" => "DENY",
    "referrer-policy" => "no-referrer"
  }

  # Only the address's own parts name a picture: a query value never stands in
  # for one of them.
  @doc "A Revstake draft's picture, or one of its sized copies."
  def launch(conn, _params), do: picture(conn, "images", conn.path_params)

  @doc "A Memestock draft's picture, or one of its sized copies."
  def stock(conn, _params), do: picture(conn, "stock-images", conn.path_params)

  defp picture(conn, lane, %{"id" => id, "digest" => digest, "size" => size}) do
    with {:ok, width} <- StoredImage.width(size),
         {:ok, key} <- StoredImage.key(lane, id, digest),
         {:ok, webp} <- StoredImage.sized_bytes(key, width) do
      send_picture(conn, "image/webp", webp, ~s("sha256-#{digest}-#{width}"))
    else
      _not_exact -> not_found(conn)
    end
  end

  defp picture(conn, lane, %{"id" => id, "digest" => digest}) do
    with {:ok, key} <- StoredImage.key(lane, id, digest),
         {:ok, %{content_type: type, bytes: bytes}} when type in @types <-
           StoredImage.original(key) do
      send_picture(conn, type, bytes, ~s("sha256-#{digest}"))
    else
      _not_exact -> not_found(conn)
    end
  end

  # The type is one of the three above and nosniff keeps the browser to it;
  # the policy lets the bytes run nothing.
  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  defp send_picture(conn, type, bytes, etag) do
    conn
    |> put_resp_content_type(type, nil)
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_resp_header("etag", etag)
    |> merge_resp_headers(@alone)
    |> send_resp(200, bytes)
  end

  defp not_found(conn), do: send_resp(conn, :not_found, "Not found")
end
