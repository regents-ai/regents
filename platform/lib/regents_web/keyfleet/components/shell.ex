defmodule RegentsWeb.Keyfleet.Components.Shell do
  @moduledoc """
  Keyfleet's frame: the site's bar, the sidebar and the page with Keyfleet's
  footer at its end.

  The bar (`RegentsWeb.Components.Shell.site_bar/1`) holds the crown, the product
  menu, the theme switch and the account control. Signed in, the account control
  is the person's picture and name with Sign out, as the site draws it where
  there is no account menu. The sidebar lists the pages the frame holds; on a
  phone Menu, under the bar, opens it as a drawer
  (`assets/js/keyfleet/shell_behavior.ts`).
  """

  use RegentsWeb, :html

  alias RegentsWeb.Components.Shell, as: SiteShell
  alias RegentsWeb.Keyfleet.RouteCatalog.RouteTarget

  attr(:route_spec, :map, required: true)
  attr(:account_control, Regents.Account.AccessContext.AccountControl, required: true)
  attr(:shell_instance, :integer, required: true)

  slot(:content, required: true)

  def shell(assigns) do
    ~H"""
    <div
      id="app-shell"
      class="rg-sheet"
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
      <SiteShell.site_bar product="keyfleet" account_control={@account_control} />

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
