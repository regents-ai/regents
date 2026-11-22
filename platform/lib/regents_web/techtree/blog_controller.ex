defmodule RegentsWeb.Techtree.BlogController do
  @moduledoc """
  Techtree's blog index and post pages under `/techtree/blog`, rendered inside
  Techtree's frame with the session's account control.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Live.Session
  alias RegentsWeb.Techtree.{Blog, Layouts}

  def index(conn, _params) do
    case Blog.all() do
      [] ->
        conn
        |> put_status(:not_found)
        |> render(:not_found, frame(conn, "Blog", Layouts.description("/techtree/blog")))

      posts ->
        render(
          conn,
          :index,
          [posts: posts] ++ frame(conn, "Blog", Layouts.description("/techtree/blog"))
        )
    end
  end

  def show(conn, %{"slug" => slug}) do
    case Blog.get(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render(:not_found, frame(conn, "Not found", Layouts.description("/techtree/blog")))

      post ->
        render(
          conn,
          :show,
          [post: post] ++
            frame(
              conn,
              post.title,
              if(post.description != "",
                do: post.description,
                else: Layouts.description("/techtree/blog")
              )
            )
        )
    end
  end

  defp frame(conn, title, description) do
    [
      page_title: title,
      page_description: description,
      current_path: conn.request_path,
      account_control: conn |> get_session() |> Session.account_control()
    ]
  end
end
