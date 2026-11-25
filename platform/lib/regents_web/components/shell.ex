defmodule RegentsWeb.Components.Shell do
  @moduledoc """
  Semantic presentation seam for Ash-owned shell behavior.

  Signed in, the account's picture and name at the top right open the account menu
  (`Regent.Account.menu`), the same on every page: the person's picture, name and
  wallet, the agents paired with the account (the `agents` slot), Pair New Agent,
  the theme switch, Manage Account and Sign out. Pair New Agent opens the pairing
  window (the `pairing_panel` slot) over the page; the agents are on the Agents
  page, and everything else about the account is on the Account page. Signed
  out, with no account menu, the bar has the theme switch and Sign in.

  The bar at the top is the site's (`site_bar/1`): the crown, the product's
  menu of every Regents product, and the account. The footer's button opens the
  list of tools agents see. On a phone, Menu opens the sidebar.
  """

  use Phoenix.Component

  alias Regents.Account.AccessContext.AccountControl
  alias RegentsWeb.Components.AgentTools

  alias RegentsWeb.RouteCatalog

  alias RegentsWeb.RouteCatalog.{
    PageTarget,
    RouteTarget,
    SidebarHeading,
    ViewerProfileTarget
  }

  attr(:route_spec, :map, required: true)
  attr(:account_control, AccountControl, required: true)
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
    # A product without a side menu of its own (`RouteCatalog`) has no Menu either,
    # and its page runs the frame's full width.
    assigns = assign(assigns, :side_menu?, assigns.route_spec.sidebar_model.targets != [])

    ~H"""
    <div
      id="app-shell"
      class="rg-sheet regents-frame"
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
      <.site_bar product={@route_spec.product} account_control={@account_control} menu>
        <:account_menu :if={@account_control.kind == :signed_in}>
          <Regent.Account.menu
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
            <:theme>
              <span class="shell-theme-label" aria-hidden="true">Light theme</span>
              <.theme_toggle id="account-menu-theme" />
            </:theme>
          </Regent.Account.menu>
        </:account_menu>
      </.site_bar>

      <Regent.Primitives.button
        :if={@side_menu?}
        variant="quiet"
        id="mobile-menu-button"
        class="mobile-menu-button"
        type="button"
        aria-controls="shell-sidebar"
        aria-expanded="false"
      >
        Menu
      </Regent.Primitives.button>

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
        :if={@side_menu?}
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
        :if={@side_menu?}
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

  attr :product, :string, required: true, doc: "the page's product, one of `Regent.Site`'s"
  attr :account_control, AccountControl, required: true

  attr :menu, :boolean,
    default: true,
    doc: """
    Signed in, the name opens the account menu (supplied in `account_menu`, or a
    built-in universal popover linking to `/account`, pairing, theme switch, and
    Sign out). When explicitly false, the bar shows the theme switch, name, and
    Sign out inline.
    """

  slot :links, doc: "the product's own links"
  slot :account_menu, doc: "`Regent.Account.menu`, when `menu` is on and someone is signed in"

  @doc """
  The site's bar (`Regent.Site.bar`) on every page: the crown, the product's menu of
  every Regents product, the product's links, and the account control.
  """
  def site_bar(assigns) do
    ~H"""
    <Regent.Site.bar id="site-bar" product={@product}>
      <:links :if={@links != []}>{render_slot(@links)}</:links>
      <:account>
        <.theme_toggle :if={!@menu or @account_control.kind != :signed_in} id="theme-control" />
        <.account_control account_control={@account_control} menu={@menu} />
        {render_slot(@account_menu)}
        <.universal_account_menu
          :if={@menu and @account_control.kind == :signed_in and @account_menu == []}
          account_control={@account_control}
        />
      </:account>
    </Regent.Site.bar>
    """
  end

  defp universal_account_menu(assigns) do
    assigns = assign(assigns, :name_is_wallet, name_is_wallet?(assigns.account_control))

    ~H"""
    <section
      id="account-menu"
      class="rg-account-menu"
      popover
      aria-label={@account_control.label}
    >
      <div class="rg-account-menu__who">
        <div :if={@account_control.avatar_src} class="rg-account-menu__picture">
          <img
            src={@account_control.avatar_src}
            referrerpolicy="no-referrer"
            width="40"
            height="40"
            alt=""
          />
        </div>
        <p class="rg-account-menu__name">
          <strong :if={!@name_is_wallet}>{@account_control.label}</strong>
          <Regent.Primitives.address
            :if={@name_is_wallet}
            id="account-menu-wallet"
            address={@account_control.wallet}
            label={@account_control.label}
          />
        </p>
        <p :if={@account_control.wallet && !@name_is_wallet} class="rg-account-menu__wallet">
          <Regent.Primitives.address
            id="account-menu-wallet"
            address={@account_control.wallet}
            label={@account_control.ens_name}
          />
        </p>
      </div>
      <div class="rg-account-menu__links">
        <a class="rg-account-menu__pair" href="/account/agents">
          <Regent.Icons.icon name="plus" /> Pair New Agent
        </a>
        <a class="rg-account-menu__pair" href="/account#account-keyfleet">
          Keyfleet Keys
        </a>
        <a class="rg-account-menu__pair" href="/techtree/account/projects">
          Techtree Projects
        </a>
        <a class="rg-account-menu__pair" href="/autolaunch/portfolio">
          Autolaunch Portfolio
        </a>
        <a class="rg-account-menu__pair" href="/patchbay/forum">
          Patchbay Forum
        </a>
      </div>
      <div class="rg-account-menu__theme">
        <span class="shell-theme-label" aria-hidden="true">Light theme</span>
        <.theme_toggle id="account-menu-theme" />
      </div>
      <div class="rg-account-menu__foot">
        <a href="/account" class="rg-button rg-button--secondary rg-button--no-arrow">
          <span class="rg-button__label">Manage Account</span>
        </a>
        <Regent.Primitives.button
          variant="secondary"
          type="button"
          arrow={false}
          data-account-target="sign-out"
        >
          Sign out
        </Regent.Primitives.button>
      </div>
    </section>
    """
  end

  defp name_is_wallet?(%{wallet: nil}), do: false

  defp name_is_wallet?(%{label: label, wallet: wallet, ens_name: ens_name}) do
    label == ens_name or
      String.downcase(label) == String.downcase(Regent.Primitives.short_address(wallet))
  end

  attr :account_control, AccountControl, required: true
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

  # The theme switch's two pictures, row by row from the top: "#" is a block. Both
  # have as many blocks, so every block of the moon flies to exactly one of the
  # sun, and both keep their outer ring clear, where a block would sit under the
  # glass's bevel and smear. The still face draws them, and the browser reads
  # them from there.
  @theme_moon [
    ".............",
    "....##.......",
    "...##.....#..",
    "..##.........",
    ".###.........",
    ".###.....#...",
    ".###.........",
    ".#####.......",
    ".######......",
    "..#########..",
    "...#######...",
    "....#####....",
    "............."
  ]

  @theme_sun [
    ".............",
    ".#....#....#.",
    "..#.......#..",
    ".....###.....",
    "....#####....",
    "...#######...",
    ".#.#######.#.",
    "...#######...",
    "....#####....",
    ".....###.....",
    "..#.......#..",
    ".#....#....#.",
    "............."
  ]

  block_count = fn rows ->
    rows |> Enum.join() |> :binary.matches("#") |> length()
  end

  if block_count.(@theme_moon) != block_count.(@theme_sun) do
    raise ArgumentError, "the theme switch's moon and sun need as many blocks"
  end

  for rows <- [@theme_moon, @theme_sun] do
    if Enum.any?(rows, &(String.length(&1) != length(rows))) do
      raise ArgumentError, "the theme switch's pictures are square"
    end

    ring = [hd(rows), List.last(rows) | Enum.map(rows, &(String.first(&1) <> String.last(&1)))]

    if Enum.any?(ring, &String.contains?(&1, "#")) do
      raise ArgumentError, "the theme switch's pictures keep their outer ring clear"
    end
  end

  attr(:id, :string, required: true)
  attr(:class, :string, default: nil, doc: "a product header's own place for it")

  @doc """
  The light and dark theme switch: a button with the role of a switch, on for
  the light theme, with a knob that slides from night on the left to day on the
  right. A press, Enter or Space turns it, and the knob can be dragged; it
  settles on the nearer side when let go.

  The server draws a still face: a flat square track and knob with the moon or
  the sun, each a picture of tiny square blocks, placed for the theme showing. Once
  the browser has drawn a first frame of the glass knob, with the same blocks
  behind it and its light, on the canvas inside (`assets/js/hooks/theme_switch.ts`,
  `assets/js/theme_switch/`), that picture takes over. Without WebGPU, with Less
  motion on or in forced colours the still face stays, and it is a whole working
  switch on its own.

  The browser owns the press: it writes the theme cookie the server reads on
  the next render, so the switch is left out of LiveView's patching, and the
  attributes the browser writes on it are kept. LiveView mounts its hook on every
  page, a plain one too, so nothing else mounts it.
  """
  def theme_toggle(assigns) do
    assigns = assign(assigns, moon: @theme_moon, sun: @theme_sun)

    ~H"""
    <div
      id={@id}
      class={["theme-switch" | List.wrap(@class)]}
      phx-hook="ThemeSwitch"
      phx-update="ignore"
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["data-theme-switch-ready", "style"])}
      data-theme-switch
    >
      <button
        id={"#{@id}-button"}
        class="theme-switch__button"
        type="button"
        role="switch"
        aria-checked="false"
        aria-label="Light theme"
      >
        <span class="theme-switch__still" aria-hidden="true">
          <span class="theme-switch__track" data-theme-switch-track>
            <span class="theme-switch__knob" data-theme-switch-knob>
              <.theme_blocks rows={@moon} class="theme-switch__moon" />
              <.theme_blocks rows={@sun} class="theme-switch__sun" />
            </span>
          </span>
        </span>
        <canvas class="theme-switch__canvas" data-theme-switch-canvas aria-hidden="true"></canvas>
      </button>
    </div>
    """
  end

  attr(:rows, :list, required: true)
  attr(:class, :string, required: true)

  # One of the switch's pictures, a block for each "#", one unit square apiece
  # with a hairline between neighbours.
  defp theme_blocks(assigns) do
    assigns = assign(assigns, size: length(assigns.rows), blocks: blocks(assigns.rows))

    ~H"""
    <svg
      class={@class}
      viewBox={"0 0 #{@size} #{@size}"}
      shape-rendering="crispEdges"
      aria-hidden="true"
    >
      <g transform="translate(0.06 0.06)">
        <rect :for={{x, y} <- @blocks} x={x} y={y} width="0.88" height="0.88" />
      </g>
    </svg>
    """
  end

  defp blocks(rows) do
    for {row, y} <- Enum.with_index(rows),
        {"#", x} <- Enum.with_index(String.graphemes(row)),
        do: {x, y}
  end

  attr(:target, :map, required: true)
  attr(:route_spec, :map, required: true)
  attr(:account_control, AccountControl, required: true)

  # A link to another product's page loads it in full, so the page wears that
  # product's look (`data-product` is written once, when the page loads).
  defp sidebar_target(%{target: %RouteTarget{} = target} = assigns) do
    assigns = assign(assigns, target: target, away?: away?(assigns.route_spec, target.route_id))

    ~H"""
    <.link
      href={@target.path}
      patch={if !@away?, do: @target.path}
      aria-current={if current?(@route_spec, @target.path), do: "page"}
    >
      {@target.label}
    </.link>
    """
  end

  defp sidebar_target(%{target: %PageTarget{} = target} = assigns) do
    assigns = assign(assigns, target: target, away?: away?(assigns.route_spec, target.route_id))

    ~H"""
    <.link
      href={@target.path}
      navigate={if !@away?, do: @target.path}
      aria-current={if @route_spec.destination == @target.path, do: "page"}
    >{@target.label}</.link>
    """
  end

  defp sidebar_target(%{target: %ViewerProfileTarget{} = target} = assigns) do
    assigns =
      assign(assigns, target: target, away?: away?(assigns.route_spec, :regent_profile))

    ~H"""
    <.link
      :if={@account_control.profile_path}
      href={@account_control.profile_path}
      patch={if !@away?, do: @account_control.profile_path}
    >
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

  defp away?(route_spec, route_id), do: RouteCatalog.product(route_id) != route_spec.product

  # A sidebar entry is current on its own page and on every tab of that page,
  # so Account stays marked on Agents, Points, Wallets, Connections and Names.
  defp current?(route_spec, path),
    do: path in [route_spec.destination | Enum.map(route_spec.tabs, & &1.path)]

  attr :account_control, AccountControl, required: true

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
end
