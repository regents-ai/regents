defmodule RegentsWeb.BlogCoverController do
  @moduledoc "Only published posts' cover images are public."
  use RegentsWeb, :controller

  # sobelow_skip ["XSS.SendResp", "XSS.ContentType"]
  def show(conn, %{"slug" => slug}) do
    case Regents.Blog.get_cover!(slug) do
      nil ->
        send_resp(conn, :not_found, "Not found")

      post ->
        conn
        |> put_resp_content_type(post.cover_type, nil)
        |> put_resp_header("cache-control", "public, max-age=0, must-revalidate")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(200, post.cover)
    end
  end
end
