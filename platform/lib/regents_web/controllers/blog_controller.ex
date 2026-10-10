defmodule RegentsWeb.BlogController do
  use RegentsWeb, :controller
  # Keep published article addresses working after the move into Reading.
  def index(conn, _params), do: conn |> put_status(:moved_permanently) |> redirect(to: "/blog")

  def show(conn, %{"slug" => slug}),
    do:
      conn
      |> put_status(:moved_permanently)
      |> redirect(to: "/blog/#{URI.encode(slug, &URI.char_unreserved?/1)}")
end
