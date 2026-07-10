defmodule AshPlatformWeb.ShellLive do
  use AshPlatformWeb, :live_view

  import AshPlatformWeb.Components.Shell

  alias AshPlatform.{AccessContext, ContentCoordinator}
  alias AshPlatformWeb.RouteCatalog

  @impl true
  def mount(params, _session, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)
    access_context = AccessContext.anonymous()

    {:ok,
     assign(socket,
       access_context: access_context,
       account_control: AccessContext.account_control(access_context),
       app_targets: RouteCatalog.app_targets(),
       content: nil,
       content_error: nil,
       content_async_name: nil,
       content_generation: 0,
       content_status: :loading,
       presentation: initial_presentation(route_spec),
       formation_panel: initial_formation_panel(route_spec),
       route_spec: route_spec,
       shell_instance: System.unique_integer([:positive, :monotonic])
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)
    generation = socket.assigns.content_generation + 1

    socket = cancel_content(socket)

    socket =
      assign(socket,
        content: nil,
        content_async_name: nil,
        content_error: nil,
        content_generation: generation,
        content_status: :loading,
        presentation: initial_presentation(route_spec),
        formation_panel: initial_formation_panel(route_spec),
        route_spec: route_spec
      )

    if connected?(socket) do
      name = {:content, generation}

      socket =
        socket
        |> assign(content_async_name: name)
        |> start_async(name, fn ->
          ContentCoordinator.load(generation, route_spec, params)
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(
        {:content, generation},
        {:ok, {generation, result}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    case result do
      {:ok, content} ->
        {:noreply,
         assign(socket,
           content: content,
           content_status: :ready,
           content_async_name: nil
         )}

      {:error, reason} ->
        {:noreply, content_failed(socket, reason)}
    end
  end

  def handle_async({:content, _generation}, {:ok, _result}, socket), do: {:noreply, socket}

  def handle_async(
        {:content, generation},
        {:exit, reason},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply, content_failed(socket, reason)}
  end

  def handle_async({:content, _generation}, {:exit, _reason}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      app_targets={@app_targets}
      account_control={@account_control}
      content_status={@content_status}
      presentation={@presentation}
      formation_panel={@formation_panel}
      shell_instance={@shell_instance}
    >
      <:content>
        <section :if={@content_status == :loading} class="shell-status" aria-busy="true">
          <h1>{@route_spec.page_display_label}</h1>
          <p>Loading this view</p>
        </section>

        <section :if={@content_status == :error} class="shell-status" role="alert">
          <h1>{@route_spec.page_display_label}</h1>
          <p>This view could not be loaded. Navigation remains available.</p>
        </section>

        <article :if={@content_status == :ready}>
          <p>{@content.eyebrow}</p>
          <p><span aria-label="Capability status">{@content.status}</span></p>
          <h1>{@content.title}</h1>
          <p>{@content.summary}</p>
          <dl :if={@content.details != []}>
            <div :for={{label, value} <- @content.details}>
              <dt>{label}</dt>
              <dd>{value}</dd>
            </div>
          </dl>
        </article>
      </:content>
    </.shell>
    """
  end

  defp content_failed(socket, reason) do
    assign(socket,
      content: nil,
      content_error: inspect(reason),
      content_status: :error,
      content_async_name: nil
    )
  end

  defp cancel_content(%{assigns: %{content_async_name: nil}} = socket), do: socket

  defp cancel_content(%{assigns: %{content_async_name: name}} = socket) do
    cancel_async(socket, name)
  end

  defp initial_presentation(%{local_state: %{presentation: %{default: presentation}}}),
    do: presentation

  defp initial_presentation(_route_spec), do: :none

  defp initial_formation_panel(%{local_state: %{panel: %{default: panel}}}), do: panel
  defp initial_formation_panel(_route_spec), do: :none
end
