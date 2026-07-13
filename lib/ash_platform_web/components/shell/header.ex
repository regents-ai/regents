defmodule AshPlatformWeb.Components.Shell.Header do
  @moduledoc false

  use Phoenix.Component

  attr(:route_spec, :map, required: true)
  attr(:app_targets, :list, required: true)
  attr(:account_control, AshPlatform.AccessContext.AccountControl, required: true)

  def header(assigns) do
    ~H"""
    <header id="shell-header" class="shell-header">
      <button
        id="mobile-menu-button"
        class="mobile-menu-button"
        type="button"
        aria-controls="shell-sidebar"
        aria-expanded="false"
      >
        Menu
      </button>

      <details id="app-selector" class="app-selector">
        <summary class="app-selector__summary">
          <img
            class="app-selector__crown"
            src="/images/brand/regents-crown-flat-dark.svg"
            alt=""
            width="252"
            height="186"
          />
          <span class="app-selector__label">{@route_spec.app_display_label}</span>
          <span class="app-selector__chevron" aria-hidden="true">⌄</span>
        </summary>
        <nav id="app-selector-menu" class="app-selector__menu" aria-label="Applications">
          <.link
            :for={target <- @app_targets}
            patch={target.path}
            aria-current={if target.app_id == @route_spec.app_id, do: "page"}
          >
            {target.label}
          </.link>
        </nav>
      </details>

      <div class="shell-header__local" data-header-controls={@route_spec.app_id}>
        <span class="shell-header__page-label">{@route_spec.page_display_label}</span>
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
          <summary class="account-menu__summary">
            <span class="account-avatar" aria-hidden="true">
              <img
                :if={@account_control.avatar_data_uri}
                src={@account_control.avatar_data_uri}
                alt=""
              />
              <span :if={!@account_control.avatar_data_uri} class="account-avatar__fallback">
                {String.first(@account_control.label)}
              </span>
            </span>
            <span data-account-target="identity">{@account_control.label}</span>
            <span class="account-menu__chevron" aria-hidden="true">⌄</span>
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
              :if={@account_control.settings_path}
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
    </header>
    """
  end
end
