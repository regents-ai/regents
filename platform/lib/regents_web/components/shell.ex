defmodule RegentsWeb.Components.Shell do
  @moduledoc "Semantic presentation seam for Ash-owned shell behavior."

  use Phoenix.Component

  alias RegentsWeb.Components.RegentLinks

  alias RegentsWeb.RouteCatalog.{
    RouteTarget,
    SidebarHeading,
    ViewerProfileTarget
  }

  attr(:route_spec, :map, required: true)
  attr(:account_control, Regents.AccessContext.AccountControl, required: true)
  attr(:shell_instance, :integer, required: true)

  attr(:credits, Decimal,
    default: nil,
    doc: "The Credits available to spend; nil when signed out."
  )

  slot(:content, required: true)
  slot(:credits_panel, doc: "The Buy Credits panel, opened from the header's balance.")

  def shell(assigns) do
    ~H"""
    <div
      id="app-shell"
      class="rg-sheet rg-frame"
      phx-hook="ShellBehavior"
      data-app={@route_spec.app_id}
      data-variant={RegentsWeb.Motion.standard("tabs")}
      data-background={@route_spec.background_slot}
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
        <.theme_toggle id="theme-control" />
        <div class="rl-header-links">
          <RegentLinks.header_links id="shell-token-menu" />
        </div>

        <button
          :if={@credits}
          id="shell-credits-button"
          class="shell-credits"
          type="button"
          aria-haspopup="dialog"
          aria-controls="shell-credits"
          aria-label={RegentCredits.Amount.format(@credits)}
          phx-click={Phoenix.LiveView.JS.dispatch("regents:open", to: "#shell-credits")}
        >
          <.credits_amount amount={@credits} />
        </button>

        <.account_control account_control={@account_control} />
      </header>

      <dialog
        :if={@credits_panel != []}
        id="shell-credits"
        class="shell-credits-dialog"
        aria-label="Buy Credits"
        phx-hook="InfoDialog"
      >
        <form method="dialog" class="shell-credits-dialog__close">
          <Regent.Primitives.button variant="quiet" type="submit" value="close">
            Close
          </Regent.Primitives.button>
        </form>
        {render_slot(@credits_panel)}
      </dialog>

      <nav
        id="shell-sidebar"
        data-panel="drawer"
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
        data-backdrop
        aria-label="Close navigation"
        hidden
      ></Regent.Primitives.button>

      <div id="app-shell-scroller" tabindex="-1">
        <main id="route-content">
          {render_slot(@content)}
        </main>
        <RegentsWeb.Layouts.product_links />
      </div>
    </div>
    """
  end

  attr(:amount, Decimal, required: true)

  # "12.40 Credits", whose unit a phone's header leaves out for room.
  defp credits_amount(assigns) do
    [number, unit] = String.split(RegentCredits.Amount.format(assigns.amount), " ", parts: 2)
    assigns = assign(assigns, number: number, unit: unit)

    ~H"""
    {@number} <span class="shell-credits__unit">{@unit}</span>
    """
  end

  attr :account_control, Regents.AccessContext.AccountControl, required: true
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
        <div class="account-menu__content shell-popover" data-panel="menu">
          <.link
            patch="/account"
            class="account-menu__row account-menu__row--account"
            data-account-menu-item="account"
          >
            <.account_menu_icon name={:settings} /><span>Account</span>
          </.link>
          <.link
            :if={@profile_links && @account_control.profile_path}
            patch={@account_control.profile_path}
            class="account-menu__row"
            data-account-menu-item="profile"
          >
            <.account_menu_icon name={:profile} /><span>Profile</span>
          </.link>
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

  @doc """
  The colour theme switch: one control that flips between the two themes.

  It names the theme showing by itself, from the page's theme or the device's
  setting, so the server passes no theme. The browser owns the press: it writes
  the theme cookie the server reads on the next render and restyles the page, so
  the control is left out of LiveView's patching.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div id={@id} class="theme-control" phx-update="ignore">
      <Regent.ThemeToggle.button id={"#{@id}-button"} data-theme-toggle />
    </div>
    """
  end

  attr(:target, :map, required: true)
  attr(:route_spec, :map, required: true)
  attr(:account_control, Regents.AccessContext.AccountControl, required: true)

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

  defp sidebar_target(%{target: %SidebarHeading{} = heading} = assigns) do
    assigns = assign(assigns, :heading, heading)

    ~H"""
    <span class="shell-sidebar__heading">{@heading.label}</span>
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
