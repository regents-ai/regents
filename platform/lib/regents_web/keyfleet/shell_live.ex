defmodule RegentsWeb.Keyfleet.ShellLive do
  @moduledoc """
  One LiveView holds Keyfleet's frame (`RegentsWeb.Keyfleet.Components.Shell`)
  across every page it draws and patches between them, so the frame never
  remounts on navigation. Each page is named by its live action
  (`RegentsWeb.Keyfleet.RouteCatalog`); so far they are the reading pages
  (`RegentsWeb.Keyfleet.Components.Reading`). Who is signed in comes from the
  site's own session (`RegentsWeb.Live.Session`).
  """

  use RegentsWeb, :live_view

  import RegentsWeb.Keyfleet.Components.Shell

  alias RegentsWeb.Keyfleet.Components.Reading
  alias RegentsWeb.Keyfleet.{PublicDocuments, RouteCatalog}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       route_spec: nil,
       shell_instance: System.unique_integer([:positive, :monotonic])
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)

    {:noreply,
     socket
     |> assign(route_spec: route_spec)
     |> assign(PublicDocuments.page(route_spec))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      account_control={@account_control}
      shell_instance={@shell_instance}
    >
      <:content>
        <Reading.page path={@route_spec.destination} />
      </:content>
    </.shell>
    """
  end
end
