defmodule AshPlatformWeb.Components.Shell do
  @moduledoc "Semantic presentation seam for Ash-owned shell behavior."

  use Phoenix.Component

  alias AshPlatformWeb.RouteCatalog.{
    FormationPanelTarget,
    RouteTarget,
    TreeTarget,
    ViewerProfileTarget
  }

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
      <header id="shell-header">
        <button
          id="mobile-menu-button"
          class="mobile-menu-button"
          type="button"
          aria-controls="shell-sidebar"
          aria-expanded="false"
        >
          Menu
        </button>

        <span aria-hidden="true">♛</span>
        <strong>{@route_spec.app_display_label}</strong>

        <nav class="app-switcher" aria-label="Applications">
          <.link :for={target <- @app_targets} patch={target.path}>{target.label}</.link>
        </nav>

        <span class="shell-spacer" />

        <label :if={@route_spec.search_kind != :none}>
          <span>Search</span>
          <input type="search" name="search" autocomplete="off" />
        </label>

        <div
          :if={@account_control.kind == :sign_in}
          class="theme-menu"
          role="group"
          aria-label="Theme"
        >
          <button type="button" data-theme-choice="system">System</button>
          <button type="button" data-theme-choice="light">Light</button>
          <button type="button" data-theme-choice="dark">Dark</button>
        </div>

        <div id="account-control" class="account-control">
          <button
            :if={@account_control.kind == :sign_in}
            type="button"
            data-account-target="sign-in"
          >
            {@account_control.label}
          </button>
          <details :if={@account_control.kind == :signed_in} id="account-menu">
            <summary>
              <span data-account-target="identity">{@account_control.label}</span>
            </summary>
            <div class="account-menu__content">
              <.link
                :if={@account_control.profile_path}
                patch={@account_control.profile_path}
                data-account-menu-item="profile"
              >
                Profile
              </.link>
              <.link
                patch={@account_control.settings_path}
                data-account-menu-item="settings"
              >
                Settings
              </.link>
              <button
                type="button"
                data-account-menu-item="log-out"
                data-account-target="sign-out"
              >
                Log Out
              </button>
            </div>
          </details>
        </div>
      </header>

      <nav id="shell-sidebar" aria-label="Context navigation">
        <ul>
          <li :for={target <- @route_spec.sidebar_model.targets}>
            <.sidebar_target
              target={target}
              route_spec={@route_spec}
              presentation={@presentation}
              formation_panel={@formation_panel}
            />
          </li>
        </ul>
      </nav>

      <div id="app-shell-scroller" tabindex="-1">
        <main id="route-content" aria-busy={@content_status == :loading}>
          {render_slot(@content)}
        </main>
      </div>
    </div>
    """
  end

  attr(:target, :map, required: true)
  attr(:route_spec, :map, required: true)
  attr(:presentation, :atom, required: true)
  attr(:formation_panel, :atom, required: true)

  defp sidebar_target(%{target: %RouteTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <.link patch={@target.path}>{@target.label}</.link>
    """
  end

  defp sidebar_target(%{target: %TreeTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <div data-tree={@target.tree_slug}>
      <.link patch={@target.path}>{@target.label}</.link>
      <span role="group" aria-label={"#{@target.label} presentation"}>
        <.link
          :for={presentation <- @target.presentations}
          patch={@target.path}
          data-tree-presentation={presentation}
          data-tree-path={@target.path}
          aria-label={"#{@target.label} #{presentation}"}
          aria-pressed={
            to_string(@route_spec.destination == @target.path && @presentation == presentation)
          }
        >
          {presentation |> Atom.to_string() |> String.capitalize()}
        </.link>
      </span>
    </div>
    """
  end

  defp sidebar_target(%{target: %FormationPanelTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <button
      type="button"
      data-formation-panel-choice={@target.panel}
      aria-pressed={to_string(@formation_panel == @target.panel)}
    >
      {@target.label}
    </button>
    """
  end

  defp sidebar_target(%{target: %ViewerProfileTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <.link patch="/regents/viewer">{@target.label}</.link>
    """
  end
end
