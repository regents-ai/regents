defmodule RegentsWeb.PaperPictureController do
  @moduledoc "Serves a published Paper Pro Daily picture from the database, by its paper."
  use RegentsWeb, :controller

  alias Regents.PaperProDaily
  alias RegentsWeb.PaperProDaily.ShareCard

  # The page asks for each picture at an address that changes whenever its paper is
  # saved again, so a browser may keep what it got for good. The type is one of the
  # three image types the paper allows, and nosniff keeps the browser to it.
  # sobelow_skip ["XSS.SendResp", "XSS.ContentType"]
  def show(conn, %{"id" => id}) do
    case PaperProDaily.get_picture(id) do
      {:ok, %{} = paper} ->
        conn
        |> put_resp_content_type(paper.picture_type, nil)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(200, paper.picture)

      _missing ->
        # A scheduled picture may become available at midnight. Do not cache its 404.
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_content_type("text/plain")
        |> send_resp(:not_found, "Not found")
    end
  end

  def page_share(conn, _params), do: share_picture(conn, ShareCard.page())

  def paper_share(conn, %{"paper" => anchor}) do
    case PaperProDaily.get_paper_by_anchor(anchor) do
      {:ok, %{} = paper} -> share_picture(conn, ShareCard.paper(paper))
      _missing -> send_resp(conn, :not_found, "Not found")
    end
  end

  defp share_picture(conn, png) do
    conn
    |> put_resp_content_type("image/png", nil)
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_resp(200, png)
  end
end
