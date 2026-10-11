defmodule RegentsWeb.BlogController do
  use RegentsWeb, :controller
  # Keep previous gallery addresses working under the Articles name.
  def index(conn, _params),
    do: conn |> put_status(:moved_permanently) |> redirect(to: "/articles")

  def show(conn, %{"slug" => slug}),
    do:
      conn
      |> put_status(:moved_permanently)
      |> redirect(to: "/articles/#{URI.encode(slug, &URI.char_unreserved?/1)}")

  def cover(conn, %{"slug" => slug}),
    do:
      conn
      |> put_status(:moved_permanently)
      |> redirect(to: "/articles/covers/#{URI.encode(slug, &URI.char_unreserved?/1)}")
end
