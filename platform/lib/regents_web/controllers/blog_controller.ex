defmodule RegentsWeb.BlogController do
  use RegentsWeb, :controller
  alias RegentsWeb.{Blog, PublicDocuments}

  def index(conn, _params),
    do: render(conn, :index, [posts: Blog.all()] ++ PublicDocuments.page("/blog"))

  def show(conn, %{"slug" => slug}) do
    case Blog.get(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render(:not_found, PublicDocuments.page(:blog_post_not_found))

      post ->
        render(conn, :show, [post: post] ++ PublicDocuments.page({:blog_post, post}))
    end
  end
end
