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

  `site_bar/1` chooses the workspace sidebar for apps and guides, and the
  marketing header for public pages. The footer opens the list of agent tools.
  """

  use Phoenix.Component

  alias Regents.Account.AccessContext.AccountControl
  alias RegentsWeb.Components.{AgentTools, AppSidebar, Marketing}

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
      <.site_bar
        product={@route_spec.product}
        account_control={@account_control}
        current_path={@route_spec.destination}
        sidebar_guides={docs_navigation(@route_spec.destination)}
        menu
      >
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
              <.theme_toggle id="account-menu-theme" />
            </:theme>
          </Regent.Account.menu>
        </:account_menu>
      </.site_bar>

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

      <div id="app-shell-scroller" tabindex="-1">
        <main id="route-content">
          {render_slot(@content)}
        </main>
        <RegentsWeb.Layouts.product_links agent_tools />
      </div>

      <AgentTools.dialog id="shell-agent-tools" />
    </div>
    """
  end

  attr :current_path, :string, default: nil
  attr :sidebar_section, :string, default: nil
  attr :sidebar_links, :list, default: []
  attr :sidebar_guides, :map, default: nil
  attr :product, :string, required: true, doc: "the page's product, one of `Regent.Site`'s"
  attr :account_control, AccountControl, default: nil

  attr :menu, :boolean,
    default: true,
    doc: """
    Signed in, the name opens the account menu (supplied in `account_menu`, or a
    built-in universal popover linking to `/account`, pairing, theme switch, and
    Sign out). When explicitly false, the bar shows the theme switch, name, and
    Sign out inline.
    """

  slot :workspace_actions, doc: "actions kept beside the account controls"
  slot :account_menu, doc: "`Regent.Account.menu`, when `menu` is on and someone is signed in"

  @doc """
  The workspace sidebar for apps and guides, or the marketing header for public reading.
  """
  def site_bar(assigns) do
    ~H"""
    <%= if AppSidebar.workspace?(@current_path) do %>
      <AppSidebar.bar
        path={@current_path}
        product={@product}
        section_path={@sidebar_section}
        extra_links={@sidebar_links}
        guides={@sidebar_guides}
      >
        <:controls>
          {render_slot(@workspace_actions)}
          <.site_account {assigns} />
        </:controls>
      </AppSidebar.bar>
    <% else %>
      <Marketing.navigation current={@product}>
        <:actions><.site_account {assigns} /></:actions>
      </Marketing.navigation>
    <% end %>
    """
  end

  defp docs_navigation("/docs") do
    products = RegentsWeb.Docs.Pages.products()
    %{title: "Docs", groups: [{"Product guides", Enum.map(products, &{&1.name, &1.home_path})}]}
  end

  defp docs_navigation("/docs/" <> _ = path) do
    alias RegentsWeb.Docs.Pages

    with %{product: id} <- Pages.page(path),
         %{name: name, groups: groups} <- Pages.product(id) do
      %{
        title: name <> " Docs",
        groups:
          Enum.map(groups, &{&1.name, Enum.map(&1.pages, fn page -> {page.name, page.path} end)})
      }
    end
  end

  defp docs_navigation(_path), do: nil

  defp site_account(%{account_control: nil} = assigns) do
    ~H"""
    <.theme_toggle id="theme-control" />
    """
  end

  defp site_account(assigns) do
    ~H"""
    <.theme_toggle :if={!@menu or @account_control.kind != :signed_in} id="theme-control" />
    <.account_control account_control={@account_control} menu={@menu} />
    {render_slot(@account_menu)}
    <.universal_account_menu
      :if={@menu and @account_control.kind == :signed_in and @account_menu == []}
      account_control={@account_control}
    />
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
