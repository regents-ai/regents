defmodule AshPlatformWeb.HomeLive do
  use AshPlatformWeb, :live_view

  alias AshPlatformWeb.RouteCatalog

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, route_spec: RouteCatalog.fetch!(:home))}

  def render(assigns) do
    ~H"""
    <main id="public-home">
      <h1>Regent</h1><.link navigate={~p"/app"}>Enter Regent</.link>
    </main>
    """
  end
end
