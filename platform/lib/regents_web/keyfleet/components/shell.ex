defmodule RegentsWeb.Keyfleet.Components.Shell do
  @moduledoc """
  Keyfleet's frame: the shared `one-site` workspace bar/sidebar, the scrolling
  page, Keyfleet's footer, and the "Buy Key" window (`RegentsWeb.Keyfleet.Components.BuyKey`)
  drawn in the `buy_key` slot.
  """

  use RegentsWeb, :html

  alias RegentsWeb.Components.Shell, as: SiteShell

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
end
