defmodule RegentsWeb.Patchbay.BlogHTML do
  @moduledoc "Patchbay's blog index, a post, and the page for a post that is not there."

  use RegentsWeb, :html

  def index(assigns), do: page(Map.put(assigns, :view, :index))
  def show(assigns), do: page(Map.put(assigns, :view, :show))
  def not_found(assigns), do: page(Map.put(assigns, :view, :not_found))

  defp page(assigns) do
    ~H"""
    <main id="blog-content">
      <Regent.Blog.gallery
        :if={@view == :index}
        posts={@posts}
        name="Blog"
        path="/patchbay/blog"
      />
      <Regent.Blog.article :if={@view == :show} post={@post} name="Blog" path="/patchbay/blog" />
      <Regent.Blog.not_found :if={@view == :not_found} name="Blog" path="/patchbay/blog" />
    </main>
    """
  end
end
