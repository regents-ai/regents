defmodule RegentsWeb.Components.Shell do
  @moduledoc """
  Semantic presentation seam for Ash-owned shell behavior.

  The side panel's open and closed state is the browser's
  (`assets/js/shell_panels.ts` and the `regents_aside` cookie, read into
  `<html data-aside>`), so the server never stores it.

  The right side bar and its button are there only for someone signed in, so a
  page signed out has nothing beside the Sign in button. It holds the box to
  pair an agent (the `pairing` slot) and a link to the agents on the Account page.
  A page that shows its own pairing box leaves the slot out, and the side panel
  then has neither.

  The top bar's nine-dot button opens the Regents Products menu, and the
  footer's button the list of tools agents see.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias RegentsWeb.Components.{AgentTools, RegentLinks}

  alias RegentsWeb.RouteCatalog.{
    PageTarget,
    RouteTarget,
    SidebarHeading,
    ViewerProfileTarget
  }

  # The Regents Products, each shown with the crown in its own pair of brand
  # colours. The other sites open in a new tab; this site's own page does not.
  @regents_apps [
    %{name: "Patchbay", href: "https://patchbay.help", tone: "patchbay", away?: true},
    %{name: "Autolaunch", href: "https://autolaunch.sh", tone: "autolaunch", away?: true},
    %{name: "Keyfleet", href: "https://keyfleet.ai", tone: "keyfleet", away?: true},
    %{name: "Techtree", href: "https://techtree.sh", tone: "techtree", away?: true},
    %{name: "$REGENT Staking", href: "/stake", tone: "protocol", away?: false}
  ]

  attr(:route_spec, :map, required: true)
  attr(:account_control, Regents.AccessContext.AccountControl, required: true)
  attr(:shell_instance, :integer, required: true)

  attr(:credits, :map,
    default: nil,
    doc: "The account's Credits reading (`state` and `value`); nil when signed out."
  )

  slot(:content, required: true)
  slot(:credits_panel, doc: "The Buy Credits panel, opened from the header's balance.")

  slot(:pairing, doc: "The box to pair an agent, in the side panel.")
  slot(:agents, doc: "The agents paired with the account, in the side panel.")

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
        <.link id="shell-brand" class="shell-brand" href="/" aria-label="Regents Labs home">
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

        <.apps_menu />

        <button
          :if={@credits}
          id="shell-credits-button"
          class="shell-credits"
          type="button"
          aria-haspopup="dialog"
          aria-controls="shell-credits"
          aria-label={credits_label(@credits)}
          phx-click={Phoenix.LiveView.JS.dispatch("regents:open", to: "#shell-credits")}
          phx-hook="MotionCount"
          data-variant="flash"
        >
          <.credits_amount amount={@credits} />
        </button>

        <.account_control account_control={@account_control} />

        <button
          :if={@account_control.kind == :signed_in}
          id="shell-aside-button"
          class="shell-tool"
          type="button"
          aria-controls="shell-aside"
          aria-expanded="false"
          aria-label="Side panel"
          data-aside-toggle
          phx-mounted={JS.ignore_attributes(["aria-expanded"])}
        >
          <.icon name={:panel} />
        </button>
      </header>

      <dialog
        :if={@credits_panel != []}
        id="shell-credits"
        class="shell-credits-dialog"
        aria-label="Buy Credits"
        phx-hook="InfoDialog"
      >
        <form method="dialog">
          <Regent.Primitives.button
            variant="quiet"
            type="submit"
            value="close"
            class="shell-credits-dialog__close"
            aria-label="Close"
          >
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
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
        <RegentsWeb.Layouts.product_links agent_tools />
      </div>

      <aside
        :if={@account_control.kind == :signed_in}
        id="shell-aside"
        aria-label="Your account and agents"
        tabindex="-1"
      >
        <div id="shell-account" class="shell-aside__head">
          <Regent.Primitives.button
            variant="secondary"
            type="button"
            data-account-target="sign-out"
          >
            Sign out
          </Regent.Primitives.button>
          <.link patch="/account" class="rg-button rg-button--secondary">Manage Account</.link>
        </div>

        {render_slot(@agents)}

        <section :if={@pairing != []} id="shell-pairing" aria-labelledby="shell-pairing-title">
          <h2 id="shell-pairing-title">Pair New Agent</h2>
          {render_slot(@pairing)}
        </section>
      </aside>

      <AgentTools.dialog id="shell-agent-tools" />
    </div>
    """
  end

  defp credits_label(%{state: :ready, value: balance}),
    do: RegentCredits.Amount.format(balance.available)

  defp credits_label(%{state: state}) when state in [:error, :stale], do: "Credits unavailable"
  defp credits_label(_credits), do: "Credits loading"

  attr(:amount, :map, required: true)

  # "12.40 Credits", whose unit a phone's header leaves out for room. Only a
  # balance just read shows; while it is read again, or when it can't be, the
  # figure is a dash. The button and the Buy Credits panel behind it are there
  # either way.
  defp credits_amount(%{amount: %{state: :ready, value: balance}} = assigns) do
    [number, unit] = String.split(RegentCredits.Amount.format(balance.available), " ", parts: 2)
    assigns = assign(assigns, number: number, unit: unit)

    ~H"""
    <span data-count>{@number}</span> <span class="shell-credits__unit">{@unit}</span>
    """
  end

  defp credits_amount(assigns),
    do: ~H"""
    <span data-count>—</span> <span class="shell-credits__unit">Credits</span>
    """

  attr :account_control, Regents.AccessContext.AccountControl, required: true
  attr :enabled, :boolean, default: true

  attr :panel, :boolean,
    default: true,
    doc: """
    Signed in, the name opens the side panel, which holds Account and Sign out.
    A page without the side panel (the local Privy reference) shows Sign out
    beside the name.
    """

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
      <button
        :if={@panel and @account_control.kind == :signed_in}
        id="account-chip"
        class="account-chip"
        type="button"
        aria-controls="shell-aside"
        aria-expanded="false"
        data-aside-toggle
        phx-mounted={JS.ignore_attributes(["aria-expanded"])}
      >
        <.account_name account_control={@account_control} />
      </button>
      <%= if !@panel and @account_control.kind == :signed_in do %>
        <span class="account-chip"><.account_name account_control={@account_control} /></span>
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          disabled={!@enabled}
          data-account-target="sign-out"
        >
          Sign out
        </Regent.Primitives.button>
      <% end %>
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
      aria-current={
        if @route_spec.destination == @target.path or
             (@target.route_id == :blog and @route_spec.route_id in [:blog_post, :articles_admin]),
           do: "page"
      }
    >
      {@target.label}
    </.link>
    """
  end

  defp sidebar_target(%{target: %PageTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <.link
      navigate={@target.path}
      aria-current={if @route_spec.destination == @target.path, do: "page"}
    >{@target.label}</.link>
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

  attr :account_control, Regents.AccessContext.AccountControl, required: true

  # The account's picture and name. The `profile` marker tells the browser the
  # page was drawn for a signed-in account.
  defp account_name(assigns) do
    ~H"""
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
    <span class="account-name" data-account-target="profile">{@account_control.label}</span>
    """
  end

  attr(:name, :atom, required: true)

  defp icon(assigns) do
    ~H"""
    <svg
      class="shell-icon"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="square"
      aria-hidden="true"
    >
      <path :if={@name == :panel} d="M3 4h18v16H3zM15 4v16" />
      <g :if={@name == :apps} fill="currentColor" stroke="none">
        <rect :for={{x, y} <- nine_dots()} x={x} y={y} width="4.5" height="4.5" />
      </g>
    </svg>
    """
  end

  # The browser opens and closes the panel itself (`popover`), so it closes on
  # Escape or a press anywhere else, and a page update never shuts it.
  defp apps_menu(assigns) do
    assigns = assign(assigns, :apps, @regents_apps)

    ~H"""
    <button
      id="shell-apps-button"
      class="shell-tool"
      type="button"
      popovertarget="shell-apps"
      aria-label="Regents Products"
    >
      <.icon name={:apps} />
    </button>
    <nav id="shell-apps" class="shell-apps" popover aria-labelledby="shell-apps-title">
      <h2 id="shell-apps-title">Regents Products</h2>
      <ul>
        <li :for={app <- @apps}>
          <a href={app.href} target={app.away? && "_blank"} rel={app.away? && "noopener"}>
            <span class="shell-apps__tile" data-tone={app.tone}>
              <RegentLinks.source_icon kind={:regent} />
            </span>
            <span>{app.name}</span>
          </a>
        </li>
      </ul>
    </nav>
    """
  end

  defp nine_dots, do: for(y <- [1.5, 9.75, 18], x <- [1.5, 9.75, 18], do: {x, y})
end
