defmodule RegentsWeb.Keyfleet.Components.Shell do
  @moduledoc """
  Keyfleet's frame: the site's bar, the sidebar and the page with Keyfleet's
  footer at its end.

  The bar (`RegentsWeb.Components.Shell.site_bar/1`) holds the crown, the product
  menu, the theme switch and the account control (with the site's universal
  account menu when signed in). The sidebar lists the pages the frame holds; on a
  phone Menu, under the bar, opens it as a drawer
  (`assets/js/keyfleet/shell_behavior.ts`).

  Every page in the frame holds the "Buy Key" window a fleet's "Buy Key" opens
  (`RegentsWeb.Keyfleet.Components.BuyKey`), drawn in the `buy_key` slot.
  """

  use RegentsWeb, :html

  alias RegentsWeb.Components.Shell, as: SiteShell
  alias RegentsWeb.Keyfleet.RouteCatalog.RouteTarget

  attr(:route_spec, :map, required: true)
  attr(:account_control, Regents.Account.AccessContext.AccountControl, required: true)
  attr(:shell_instance, :integer, required: true)

  slot(:content, required: true)
  slot(:buy_key, doc: "The \"Buy Key\" window, while it is open.")

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
      <SiteShell.site_bar
        product="keyfleet"
        account_control={@account_control}
        current_path={@route_spec.destination}
      />

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
        <main id="route-content" tabindex="-1">
          {render_slot(@content)}
        </main>
        <RegentsWeb.Keyfleet.Layouts.product_links />
      </div>

      {render_slot(@buy_key)}
    </div>
    """
  end

  attr :id, :string, required: true

  @doc """
  Pair New Agent, a link to the site's own page for it (`/pair`).
  """
  def pair_button(assigns) do
    ~H"""
    <.link
      id={@id}
      href={~p"/pair"}
      class="rg-button rg-button--secondary rg-button--no-arrow"
    >
      <span class="rg-button__label">Pair New Agent</span>
    </.link>
    """
  end

  attr(:target, :map, required: true)
  attr(:route_spec, :map, required: true)
  attr(:account_control, Regents.Account.AccessContext.AccountControl, required: true)

  # Signed out, the sidebar's "Sign in" opens sign-in in place (matching the
  # header control) rather than navigating away to /account. Signed in, the
  # account page is in another live session, so a plain link reaches it.
  defp sidebar_target(%{target: %RouteTarget{route_id: :account} = target} = assigns) do
    assigns = assign(assigns, :label, sidebar_label(target, assigns.account_control))

    ~H"""
    <button
      :if={@account_control.kind == :sign_in}
      type="button"
      data-account-target="sign-in"
    >
      {@label}
    </button>
    <.link :if={@account_control.kind != :sign_in} href={@target.path}>{@label}</.link>
    """
  end

  defp sidebar_target(%{target: %RouteTarget{} = target} = assigns) do
    assigns = assign(assigns, :label, sidebar_label(target, assigns.account_control))

    ~H"""
    <.link patch={@target.path} aria-current={current(@target, @route_spec)}>
      {@label}
    </.link>
    """
  end

  # A fleet stays current on every one of its pages. A listed page is the
  # location of the pages under it (an agent's page under /keyfleet/agents).
  defp current(target, route_spec) do
    cond do
      current?(target, route_spec) -> "page"
      String.starts_with?(route_spec.destination, target.path <> "/") -> "location"
      true -> nil
    end
  end

  defp current?(target, route_spec),
    do:
      Enum.any?(
        [route_spec.destination, fleet_path(route_spec.fleet_id)],
        &(&1 == target.path)
      )

  defp fleet_path(nil), do: nil
  defp fleet_path(fleet_id), do: Regents.Keyfleet.Fleets.path(fleet_id)

  # Signed out, the account page is named as the header's button names it.
  defp sidebar_label(%RouteTarget{route_id: :account}, %{kind: :sign_in, label: label}),
    do: label

  defp sidebar_label(%RouteTarget{label: label}, _account_control), do: label
end
