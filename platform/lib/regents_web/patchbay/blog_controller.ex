defmodule RegentsWeb.Patchbay.BlogController do
  @moduledoc """
  Patchbay's blog: the index and each post. A request for either one's
  Markdown is answered before the router (`RegentsWeb.Patchbay.PublicDocuments`).
  """

  use RegentsWeb, :controller

  alias RegentsWeb.Patchbay.Blog
  alias RegentsWeb.Patchbay.Layouts
  alias RegentsWeb.Patchbay.PublicDocuments

  def index(conn, _params) do
    conn
    |> merge_assigns(PublicDocuments.page("/patchbay/blog") ++ Layouts.frame(conn, []))
    |> render(:index, posts: Blog.all())
  end

  def show(conn, %{"slug" => slug}) do
    case Blog.get(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> merge_assigns(PublicDocuments.page(:post_not_found) ++ Layouts.frame(conn, []))
        |> render(:not_found)

      post ->
        conn
        |> merge_assigns(Layouts.frame(conn, [page_data(post)]))
        |> render(:show, page_title: post.title, page_description: post.description, post: post)
    end
  end

  # The article as its page shows it, for search engines and AI answers.
  defp page_data(post) do
    origin = RegentsWeb.Endpoint.url()
    image = origin |> URI.merge(post.image) |> URI.to_string()

    Regent.StructuredData.blog_posting(%{post | image: image},
      url: origin <> ~p"/patchbay/blog/#{post.slug}",
      publisher: Layouts.organization_id()
    )
  end
end
