defmodule AshPlatformWeb.Components.Shell do
  @moduledoc "Semantic presentation seam for Ash-owned shell behavior."

  use Phoenix.Component

  alias AshPlatformWeb.Components.Background
  alias AshPlatformWeb.Components.Shell.{ContentFrame, Header, Sidebar}

  attr(:route_spec, :map, required: true)
  attr(:app_targets, :list, required: true)
  attr(:account_control, AshPlatform.AccessContext.AccountControl, required: true)
  attr(:content_status, :atom, required: true)
  attr(:presentation, :atom, required: true)
  attr(:formation_panel, :atom, required: true)
  attr(:shell_instance, :integer, required: true)
  slot(:content, required: true)

  def shell(assigns) do
    ~H"""
    <div
      id="app-shell"
      phx-hook="ShellBehavior"
      data-app={@route_spec.app_id}
      data-background={@route_spec.background_slot}
      data-content-transition={@route_spec.content_transition_kind}
      data-menu-open="false"
      data-presentation={@presentation}
      data-formation-panel={@formation_panel}
      data-route-id={@route_spec.route_id}
      data-destination={@route_spec.destination}
      data-shell-instance={@shell_instance}
    >
      <Background.background slot={@route_spec.background_slot} />
      <Header.header
        route_spec={@route_spec}
        app_targets={@app_targets}
        account_control={@account_control}
      />
      <Sidebar.sidebar
        route_spec={@route_spec}
        presentation={@presentation}
        formation_panel={@formation_panel}
        viewer_profile_path={@account_control.profile_path}
      />
      <button
        class="shell-menu-scrim"
        type="button"
        data-shell-menu-scrim
        aria-label="Close navigation"
        hidden
      ></button>
      <ContentFrame.content_frame content_status={@content_status}>
        <:content>{render_slot(@content)}</:content>
      </ContentFrame.content_frame>
    </div>
    """
  end
end
