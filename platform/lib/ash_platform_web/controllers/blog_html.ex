defmodule AshPlatformWeb.BlogHTML do
  use AshPlatformWeb, :html

  def index(assigns), do: page(Map.put(assigns, :view, :index))
  def show(assigns), do: page(Map.put(assigns, :view, :show))
  def not_found(assigns), do: page(Map.put(assigns, :view, :not_found))

  defp page(assigns) do
    ~H"""
    <Regent.Structure.frame class="rl-root">
      <AshPlatformWeb.HomeLive.landing_header blog?={true} theme={@conn.assigns.theme} /><main id="main-content">
        <Regent.Blog.gallery :if={@view == :index} posts={@posts} site="Regents" />
        <Regent.Blog.article :if={@view == :show} post={@post} />
        <Regent.Blog.not_found :if={@view == :not_found} />
      </main>
    </Regent.Structure.frame>
    """
  end
end
