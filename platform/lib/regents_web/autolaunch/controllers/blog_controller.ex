defmodule RegentsWeb.Autolaunch.BlogController do
  use RegentsWeb, :controller
  alias RegentsWeb.Autolaunch.{Blog, PublicDocuments}
  alias RegentsWeb.Live.Session

  def index(conn, _params) do
    render(
      conn,
      :index,
      [posts: Blog.all()] ++ frame(conn) ++ PublicDocuments.page("/autolaunch/blog")
    )
  end

  def show(conn, %{"slug" => slug}) do
    case Blog.get(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render(:not_found, frame(conn) ++ PublicDocuments.page(:missing_post))

      post ->
        render(
          conn,
          :show,
          frame(conn) ++
            [
              page_title: post.title,
              page_description: post.description,
              post: post
            ]
        )
    end
  end

  defp frame(conn) do
    [
      current_path: conn.request_path,
      account_control: conn |> get_session() |> Session.account_control()
    ]
  end
end
