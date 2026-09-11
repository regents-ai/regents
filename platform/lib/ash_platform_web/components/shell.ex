defmodule AshPlatformWeb.Components.Shell do
  @moduledoc "Semantic presentation seam for Ash-owned shell behavior."

  use Phoenix.Component

  alias AshPlatformWeb.Components.RegentLinks

  alias AshPlatformWeb.RouteCatalog.{
    RouteTarget,
    ViewerProfileTarget
  }

  @doc """
  The short form every wallet address is named by on screen: its first four hex
  digits and its last four, as the header pill and the Stake and Redeem wallet
  pills all show them.
  """
  def short_wallet("0x" <> address) when byte_size(address) == 40,
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  def short_wallet(wallet), do: wallet

  attr(:route_spec, :map, required: true)
  attr(:account_control, AshPlatform.AccessContext.AccountControl, required: true)
  attr(:content_status, :atom, required: true)
  attr(:shell_instance, :integer, required: true)
  attr(:theme, :string, required: true)
  slot(:content, required: true)

  def shell(assigns) do
    ~H"""
    <div
      id="app-shell"
      class="rg-sheet rg-frame"
      phx-hook="ShellBehavior"
      data-app={@route_spec.app_id}
      data-motion-app={@route_spec.app_id}
      data-background={@route_spec.background_slot}
      data-content-transition={@route_spec.content_transition_kind}
      data-menu-open="false"
      data-route-id={@route_spec.route_id}
      data-destination={@route_spec.destination}
      data-shell-instance={@shell_instance}
    >
      <header id="shell-header">
        <.link id="shell-brand" class="shell-brand" href="/">
          <span class="shell-brand__mark" aria-hidden="true">
            <img
              class="shell-brand__mark-light"
              src="/images/brand/regents-crown-flat-light.svg"
              alt=""
            />
            <img
              class="shell-brand__mark-dark"
              src="/images/brand/regents-crown-flat-dark.svg"
              alt=""
            />
          </span>
          <span class="shell-brand__name">Regents Labs</span>
        </.link>

        <Regent.Primitives.button
          variant="quiet"
          id="mobile-menu-button"
          class="mobile-menu-button"
          type="button"
          aria-controls="shell-sidebar"
          aria-expanded="false"
        >
          Menu
        </Regent.Primitives.button>

        <span class="shell-spacer" />
        <.theme_toggle id="theme-control" theme={@theme} />
        <div class="rl-header-links">
          <RegentLinks.header_links id="shell-token-menu" />
        </div>

        <div class="shell-local-controls" data-motion-header-controls>
          <Regent.Primitives.field
            :if={@route_spec.search_kind != :none}
            id="shell-search"
            label="Search"
            class="shell-search"
          >
            <input id="shell-search" type="search" name="search" autocomplete="off" />
          </Regent.Primitives.field>
        </div>

        <.account_control account_control={@account_control} />
      </header>

      <nav
        id="shell-sidebar"
        data-motion-region
        aria-label="Context navigation"
        tabindex="-1"
      >
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          class="shell-menu-close"
          data-shell-menu-close
        >
          Close navigation
        </Regent.Primitives.button>
        <Regent.Primitives.field
          :if={@route_spec.search_kind != :none}
          id="shell-mobile-search"
          label="Search"
          class="shell-mobile-search"
        >
          <input id="shell-mobile-search" type="search" name="mobile-search" autocomplete="off" />
        </Regent.Primitives.field>
        <ul>
          <li
            :for={target <- @route_spec.sidebar_model.targets}
            :if={visible_sidebar_target?(target, @account_control)}
          >
            <.sidebar_target
              target={target}
              route_spec={@route_spec}
              account_control={@account_control}
            />
          </li>
        </ul>
      </nav>

      <Regent.Primitives.button
        variant="quiet"
        type="button"
        class="shell-menu-scrim"
        data-shell-menu-scrim
        aria-label="Close navigation"
        hidden
      ></Regent.Primitives.button>

      <div id="app-shell-scroller" tabindex="-1">
        <main
          id="route-content"
          data-motion-region
          aria-busy={@content_status == :loading}
        >
          {render_slot(@content)}
        </main>
      </div>
    </div>
    """
  end

  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :enabled, :boolean, default: true
  attr :profile_links, :boolean, default: true

  @doc """
  The real Regents account control, also rendered by the local Privy reference.
  These markers are consumed by auth_lazy.ts; this component never authenticates
  a user itself. The caller supplies the server-verified account presentation.
  """
  def account_control(assigns) do
    ~H"""
    <div id="account-control" class="account-control">
      <Regent.Primitives.button
        :if={@account_control.kind == :sign_in}
        type="button"
        data-account-target="sign-in"
        disabled={!@enabled}
      >
        {@account_control.label}
      </Regent.Primitives.button>
      <details :if={@account_control.kind == :signed_in} id="account-menu">
        <summary>
          <%!-- ENS avatar hosts must not learn which page the visitor is on. --%>
          <img
            :if={@account_control.avatar_src}
            class="account-avatar"
            src={@account_control.avatar_src}
            referrerpolicy="no-referrer"
            width="36"
            height="36"
            alt=""
          />
          <span data-account-target="profile">{@account_control.label}</span>
          <span class="shell-chevron" aria-hidden="true">⌄</span>
        </summary>
        <div class="account-menu__content shell-popover">
          <.link href="/profile" class="account-menu__row">Account profile</.link>
          <.link
            :if={@profile_links && @account_control.profile_path}
            patch={@account_control.profile_path}
            class="account-menu__row"
            data-account-menu-item="profile"
          >
            <.account_menu_icon name={:profile} /><span>Profile</span>
          </.link>
          <%!-- Settings returns soon (founder, 2026-09-03): switched off, not removed.
          <.link patch={@account_control.settings_path} class="account-menu__row" data-account-menu-item="settings">
            <.account_menu_icon name={:settings} /><span>Settings</span>
          </.link>
          --%>
          <Regent.Primitives.button
            variant="quiet"
            type="button"
            disabled={!@enabled}
            class="account-menu__row account-menu__row--danger"
            data-account-menu-item="disconnect"
            data-account-target="sign-out"
          >
            <.account_menu_icon name={:logout} /><span>Disconnect</span>
          </Regent.Primitives.button>
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
    """
  end

  attr(:id, :string, required: true)
  attr(:theme, :string, required: true)

  @doc """
  The colour theme switch: one control that flips between the two themes.

  The browser owns its state. It writes the theme cookie the server reads on the
  next render, and restates the current theme here on load and after every live
  navigation, so the control is left out of LiveView's patching. The server
  renders the theme it just served, so the control reads correctly before any
  script runs and for anyone browsing without one.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div id={@id} class="theme-control" phx-update="ignore">
      <Regent.ThemeToggle.button id={"#{@id}-button"} theme={@theme} data-theme-toggle />
    </div>
    """
  end

  attr(:request, :string, required: true)

  @doc """
  The answer to an on-chain click made while the browser's active wallet is not
  the one the sign-in names. It opens as a modal the moment it renders and closes
  by the visitor's hand or by the named wallet becoming active again.
  """
  def wallet_reconnect_dialog(assigns) do
    ~H"""
    <dialog
      id="wallet-reconnect-dialog"
      class="shell-reconnect-dialog"
      aria-labelledby="wallet-reconnect-heading"
      phx-hook="ModalDialog"
      data-dismiss-event="dismiss_wallet_reconnect"
    >
      <h2 id="wallet-reconnect-heading">Reconnect your wallet</h2>
      <p class="shell-reconnect-request">{@request}</p>
      <form method="dialog">
        <Regent.Primitives.button variant="secondary" type="submit" value="close">OK</Regent.Primitives.button>
      </form>
    </dialog>
    """
  end

  attr(:target, :map, required: true)
  attr(:route_spec, :map, required: true)
  attr(:account_control, AshPlatform.AccessContext.AccountControl, required: true)

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
