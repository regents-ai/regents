defmodule RegentsWeb.PaperPictureController do
  @moduledoc "Serves a Paper Pro Daily picture from the database, by the paper's day."
  use RegentsWeb, :controller

  alias Regents.PaperProDaily

  # The page asks for each picture at an address that changes whenever its paper is
  # saved again, so a browser may keep what it got for good. The type is one of the
  # three image types the paper allows, and nosniff keeps the browser to it.
  # sobelow_skip ["XSS.SendResp", "XSS.ContentType"]
  def show(conn, %{"date" => date}) do
    with {:ok, date} <- Date.from_iso8601(date),
         %{} = paper <- PaperProDaily.get_picture!(date) do
      conn
      |> put_resp_content_type(paper.picture_type, nil)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, paper.picture)
    else
      _missing ->
        conn |> put_resp_content_type("text/plain") |> send_resp(:not_found, "Not found")
    end
  end
end
