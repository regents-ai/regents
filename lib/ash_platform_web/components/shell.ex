defmodule AshPlatformWeb.Components.Shell do
  @moduledoc "Semantic presentation seam for Ash-owned shell behavior."

  use Phoenix.Component

  alias AshPlatformWeb.Components.Background

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
      data-motion-app={@route_spec.app_id}
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

      <header id="shell-header" class="shell-material shell-material--strong">
        <div id="app-selector" class="app-selector">
          <details>
            <summary aria-label={"Switch application. Current application: #{@route_spec.app_display_label}"}>
              <span class="app-selector__mark" aria-hidden="true">
                <img
                  class="app-selector__mark-light"
                  src="/images/brand/regents-crown-flat-light.svg"
                  alt=""
                />
                <img
                  class="app-selector__mark-dark"
                  src="/images/brand/regents-crown-flat-dark.svg"
                  alt=""
                />
              </span>
              <strong>{@route_spec.app_display_label}</strong>
              <span class="shell-chevron" aria-hidden="true">⌄</span>
            </summary>

            <nav class="app-switcher shell-popover" aria-label="Applications">
              <.link
                :for={target <- @app_targets}
                :if={target.app_id != @route_spec.app_id}
                patch={target.path}
              >
                {target.label}
              </.link>
            </nav>
          </details>
        </div>

        <button
          id="mobile-menu-button"
          class="mobile-menu-button"
          type="button"
          aria-controls="shell-sidebar"
          aria-expanded="false"
        >
          Menu
        </button>

        <span class="shell-spacer" />

        <div class="shell-local-controls" data-motion-header-controls>
          <label :if={@route_spec.search_kind != :none} class="shell-search">
            <span>Search</span>
            <input type="search" name="search" autocomplete="off" />
          </label>
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
              <img
                :if={@account_control.avatar_data_uri}
                class="account-avatar"
                src={@account_control.avatar_data_uri}
                width="36"
                height="36"
                alt=""
              />
              <span data-account-target="profile">{@account_control.label}</span>
              <span class="shell-chevron" aria-hidden="true">⌄</span>
            </summary>
            <div class="account-menu__content shell-popover">
              <.link
                :if={@account_control.profile_path}
                patch={@account_control.profile_path}
                class="account-menu__row"
                data-account-menu-item="profile"
              >
                <.account_menu_icon name={:profile} />
                <span>Profile</span>
              </.link>
              <.link
                patch={@account_control.settings_path}
                class="account-menu__row"
                data-account-menu-item="settings"
              >
                <.account_menu_icon name={:settings} />
                <span>Settings</span>
              </.link>
              <button
                type="button"
                class="account-menu__row account-menu__row--danger"
                data-account-menu-item="log-out"
                data-account-target="sign-out"
              >
                <.account_menu_icon name={:logout} />
                <span>Log Out</span>
              </button>
            </div>
          </details>

          <p
            id="account-auth-status"
            class="account-auth-status"
            role="status"
            aria-live="polite"
            aria-atomic="true"
            phx-update="ignore"
            hidden
          >
          </p>
        </div>

        <div :if={@account_control.kind == :sign_in} id="theme-control" class="theme-control">
          <details>
            <summary aria-label="Choose appearance">Theme <span aria-hidden="true">⌄</span></summary>
            <div class="theme-menu shell-popover" role="group" aria-label="Theme">
              <button type="button" data-theme-choice="system">System</button>
              <button type="button" data-theme-choice="light">Light</button>
              <button type="button" data-theme-choice="dark">Dark</button>
            </div>
          </details>
        </div>
      </header>

      <nav
        id="shell-sidebar"
        class="shell-material"
        data-motion-region
        aria-label="Context navigation"
      >
        <label :if={@route_spec.search_kind != :none} class="shell-mobile-search">
          <span>Search</span>
          <input type="search" name="mobile-search" autocomplete="off" />
        </label>
        <div
          :if={@account_control.kind == :sign_in}
          class="shell-mobile-theme theme-menu"
          role="group"
          aria-label="Theme"
        >
          <span>Appearance</span>
          <button type="button" data-theme-choice="system">System</button>
          <button type="button" data-theme-choice="light">Light</button>
          <button type="button" data-theme-choice="dark">Dark</button>
        </div>
        <ul>
          <li
            :for={target <- @route_spec.sidebar_model.targets}
            :if={visible_sidebar_target?(target, @account_control)}
          >
            <.sidebar_target
              target={target}
              route_spec={@route_spec}
              account_control={@account_control}
              presentation={@presentation}
              formation_panel={@formation_panel}
            />
          </li>
        </ul>
      </nav>

      <div id="app-shell-scroller" tabindex="-1">
        <main
          id="route-content"
          class="shell-material shell-material--strong"
          data-motion-region
          aria-busy={@content_status == :loading}
        >
          {render_slot(@content)}
        </main>
      </div>
    </div>
    """
  end

  attr(:target, :map, required: true)
  attr(:route_spec, :map, required: true)
  attr(:account_control, AshPlatform.AccessContext.AccountControl, required: true)
  attr(:presentation, :atom, required: true)
  attr(:formation_panel, :atom, required: true)

  defp sidebar_target(%{target: %RouteTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <.link
      patch={@target.path}
      aria-current={if @route_spec.destination == @target.path, do: "page"}
    >
      {@target.label}
    </.link>
    """
  end

  defp sidebar_target(%{target: %TreeTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <div data-tree={@target.tree_slug}>
      <.link
        patch={@target.path}
        aria-current={if @route_spec.destination == @target.path, do: "page"}
      >
        {@target.label}
      </.link>
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
    <.link :if={@account_control.profile_path} patch={@account_control.profile_path}>
      {@target.label}
    </.link>
    """
  end

  defp visible_sidebar_target?(%ViewerProfileTarget{}, %{profile_path: path}),
    do: is_binary(path) and path != ""

  defp visible_sidebar_target?(_target, _account_control), do: true

  attr(:name, :atom, required: true)

  defp account_menu_icon(assigns) do
    ~H"""
    <svg
      class="account-menu__icon"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="square"
      stroke-linejoin="miter"
      aria-hidden="true"
    >
      <g :if={@name == :profile}>
        <circle cx="12" cy="8" r="3.5" />
        <path d="M5 21v-2a7 7 0 0 1 14 0v2" />
      </g>
      <g :if={@name == :settings}>
        <circle cx="12" cy="12" r="3" />
        <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9 7 7M17 17l2.1 2.1M19.1 4.9 17 7M7 17l-2.1 2.1" />
      </g>
      <g :if={@name == :logout}>
        <path d="M10 4H4v16h6M14 8l4 4-4 4M8 12h10" />
      </g>
    </svg>
    """
  end
end
