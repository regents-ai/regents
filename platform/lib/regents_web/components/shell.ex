defmodule RegentsWeb.Components.Shell do
  @moduledoc """
  Semantic presentation seam for Ash-owned shell behavior.

  Signed in, the account's picture and name at the top right open the account menu
  (`Regent.Account.menu`), the same on every page: the person's picture, name and
  wallet, the agents paired with the account (the `agents` slot), Pair New Agent,
  Manage Account and Sign out. Pair New Agent opens the pairing window (the
  `pairing_panel` slot) over the page; the agents are on the Agents page, and
  everything else about the account is on the Account page. Signed out, the
  header has Sign in alone.

  The top bar's nine-dot button opens the Regents Products menu, and the
  footer's button the list of tools agents see.
  """

  use Phoenix.Component

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
    %{name: "Techtree", href: "https://techtree.sh", tone: "techtree", away?: true},
    %{name: "Keyfleet", href: "https://keyfleet.ai", tone: "keyfleet", away?: true},
    %{name: "$REGENT Staking", href: "/stake", tone: "protocol", away?: false}
  ]

  attr(:route_spec, :map, required: true)
  attr(:account_control, Regents.AccessContext.AccountControl, required: true)
  attr(:shell_instance, :integer, required: true)

  slot(:content, required: true)

  # Required, so a page that draws the shell without one of these does not compile:
  # signed in, it would show a menu without agents or a Pair New Agent that opens
  # nothing. A caller leaves one out for someone signed out with `:if`.
  slot(:agents, required: true, doc: "The agents paired with the account, in the account menu.")

  slot(:pairing_panel,
    required: true,
    doc: "The pairing window's box, opened by every Pair New Agent."
  )

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
      <a class="shell-skip" href="#route-content">Skip to content</a>
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

        <.account_control account_control={@account_control} />

        <Regent.Account.menu
          :if={@account_control.kind == :signed_in}
          id="account-menu"
          name={@account_control.label}
          wallet={@account_control.wallet}
          ens_name={@account_control.ens_name}
          manage_href="/account"
          pair_window="shell-pairing"
        >
          <:picture>
            <img
              :if={@account_control.avatar_src}
              src={@account_control.avatar_src}
              referrerpolicy="no-referrer"
              width="40"
              height="40"
              alt=""
            />
          </:picture>
          <:agents>{render_slot(@agents)}</:agents>
        </Regent.Account.menu>
      </header>

      <Regent.Structure.dialog
        :if={@pairing_panel != []}
        id="shell-pairing"
        class="shell-pairing-dialog"
        aria-labelledby="shell-pairing-title"
        phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["open", "data-settled"])}
      >
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          class="shell-dialog-close"
          aria-label="Close"
          data-pair-close
        >
          <Regent.Icons.icon name="x" />
        </Regent.Primitives.button>
        <h2 id="shell-pairing-title">Pair New Agent</h2>
        {render_slot(@pairing_panel)}
      </Regent.Structure.dialog>

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
        <nav
          :if={@route_spec.tabs != []}
          id="shell-tabs"
          class="shell-tabs"
          data-shell-nav
          aria-label="Account views"
        >
          <.link
            :for={tab <- @route_spec.tabs}
            patch={tab.path}
            aria-current={@route_spec.route_id == tab.route_id && "page"}
          >
            {tab.label}
          </.link>
        </nav>
        <main id="route-content">
          {render_slot(@content)}
        </main>
        <RegentsWeb.Layouts.product_links agent_tools />
      </div>

      <AgentTools.dialog id="shell-agent-tools" />
    </div>
    """
  end

  attr :account_control, Regents.AccessContext.AccountControl, required: true
  attr :enabled, :boolean, default: true

  attr :menu, :boolean,
    default: true,
    doc: """
    Signed in, the name opens the account menu, which holds Account and Sign out.
    A page without the menu (the local Privy reference) shows Sign out beside the
    name.
    """

  @doc """
  The real Regents account control, also rendered by the local Privy reference.
  These markers are consumed by auth_lazy.ts; this component never authenticates
  a user itself. The caller supplies the server-verified account presentation.
  """
  def account_control(assigns) do
    ~H"""
    <div id="account-control" class="account-control" data-account-wallet={@account_control.wallet}>
      <Regent.Primitives.button
        :if={@account_control.kind == :sign_in}
        type="button"
        data-account-target="sign-in"
        disabled={!@enabled}
      >
        {@account_control.label}
      </Regent.Primitives.button>
      <button
        :if={@menu and @account_control.kind == :signed_in}
        id="account-chip"
        class="account-chip"
        type="button"
        popovertarget="account-menu"
      >
        <.account_name account_control={@account_control} />
      </button>
      <%= if !@menu and @account_control.kind == :signed_in do %>
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
      aria-current={if @route_spec.destination == @target.path, do: "page"}
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
      <Regent.Icons.icon name="grip" class="shell-icon shell-icon--apps" />
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
end
