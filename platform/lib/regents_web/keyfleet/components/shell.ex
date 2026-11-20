defmodule RegentsWeb.Keyfleet.Components.Shell do
  @moduledoc """
  Keyfleet's frame: the header, the sidebar and the page with Keyfleet's
  footer at its end.

  The header holds the name, Menu, the site's theme switch and its account
  control (`RegentsWeb.Components.Shell`), and the Regents crown and links
  (`RegentsWeb.Keyfleet.Components.RegentLinks`). Signed in, the account control
  is the person's picture and name with Sign out, as the site draws it where
  there is no account menu. The sidebar lists the pages the frame holds; below
  a wide screen Menu opens it as a drawer
  (`assets/js/keyfleet/shell_behavior.ts`).
  """

  use RegentsWeb, :html

  alias RegentsWeb.Components.Shell, as: SiteShell
  alias RegentsWeb.Keyfleet.Components.RegentLinks
  alias RegentsWeb.Keyfleet.RouteCatalog.RouteTarget

  attr(:route_spec, :map, required: true)
  attr(:account_control, Regents.Account.AccessContext.AccountControl, required: true)
  attr(:shell_instance, :integer, required: true)

  slot(:content, required: true)

  def shell(assigns) do
    ~H"""
    <div
      id="app-shell"
      class="rg-sheet rg-frame"
      phx-hook="KeyfleetShell"
      data-app={@route_spec.app_id}
      data-variant={RegentsWeb.Motion.standard("tabs")}
      data-background={@route_spec.background_slot}
      data-menu-open="false"
      data-route-id={@route_spec.route_id}
      data-destination={@route_spec.destination}
      data-shell-instance={@shell_instance}
    >
      <a class="shell-skip" href="#route-content">Skip to content</a>
      <.header account_control={@account_control} />

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
          <li :for={target <- @route_spec.sidebar_model.targets}>
            <.sidebar_target target={target} route_spec={@route_spec} />
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
        <main id="route-content" tabindex="-1">
          {render_slot(@content)}
        </main>
        <RegentsWeb.Keyfleet.Layouts.product_links />
      </div>
    </div>
    """
  end

  attr :account_control, Regents.Account.AccessContext.AccountControl, required: true

  @doc """
  The site header: brand, Menu, the theme switch, the Regents crown and links,
  and the account control. It fits one line on a phone.
  """
  def header(assigns) do
    ~H"""
    <header id="shell-header">
      <.link id="shell-brand" class="shell-brand" href={~p"/keyfleet"} aria-label="Keyfleet">
        <span class="shell-brand__mark" aria-hidden="true">
          <img
            class="shell-brand__mark-light"
            src={~p"/images/brand/regents-crown-flat-light.svg"}
            alt=""
          />
          <img
            class="shell-brand__mark-dark"
            src={~p"/images/brand/regents-crown-flat-dark.svg"}
            alt=""
          />
        </span>
        <span class="shell-brand__name">Keyfleet</span>
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
      <SiteShell.theme_toggle id="theme-control" class="shell-header-theme" />
      <div class="rl-header-links">
        <RegentLinks.token_menu id="shell-regents-crown" />
        <RegentLinks.header_links id="shell-token-menu" />
      </div>

      <SiteShell.account_control account_control={@account_control} menu={false} />
    </header>
    """
  end

  attr(:target, RouteTarget, required: true)
  attr(:route_spec, :map, required: true)

  defp sidebar_target(assigns) do
    ~H"""
    <.link patch={@target.path} aria-current={current(@target, @route_spec)}>
      {@target.label}
    </.link>
    """
  end

  # A listed page is the location of the pages under it (an agent's page under
  # /keyfleet/agents).
  defp current(target, route_spec) do
    cond do
      route_spec.destination == target.path -> "page"
      String.starts_with?(route_spec.destination, target.path <> "/") -> "location"
      true -> nil
    end
  end
end
