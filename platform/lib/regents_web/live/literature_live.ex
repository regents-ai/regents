defmodule RegentsWeb.LiteratureLive do
  @moduledoc "The literature chart inside the reading navigation."
  use RegentsWeb, :live_view
  import RegentsWeb.Components.Shell

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       route_spec: RegentsWeb.RouteCatalog.fetch!(:literature),
       shell_instance: System.unique_integer([:positive, :monotonic]),
       books: RegentsWeb.Literature.books()
     )
     |> assign(RegentsWeb.PublicDocuments.page("/literature"))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}
  def handle_info({:ens_lookup_finished, _account_id}, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      account_control={@account_control}
      shell_instance={@shell_instance}
    >
      <:content><RegentsWeb.LiteratureHTML.show books={@books} /></:content>
    </.shell>
    """
  end
end
