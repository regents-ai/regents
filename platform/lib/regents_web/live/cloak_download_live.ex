defmodule RegentsWeb.CloakDownloadLive do
  @moduledoc """
  The `/cloak/download` page, where Download for Mac on `/cloak` leads. The
  installer (`RegentsWeb.Cloak.installer/0`) starts by itself once the page
  opens, the direct link under the heading starts the same file, two steps show
  how to install and open the app, and the Updates band
  (`RegentsWeb.Components.CloakUpdates`) takes an address for Cloak news.
  """
  use RegentsWeb, :html

  alias RegentsWeb.Cloak
  alias RegentsWeb.Components.CloakUpdates

  attr :client_tag, :string, required: true

  def page(assigns) do
    assigns = assign(assigns, :installer, Cloak.installer())

    ~H"""
    <section
      id="cloak-download-page"
      class="product-page cloak-download-page"
      aria-labelledby="product-heading"
    >
      <header class="product-heading cloak-download-page__heading rg-panel rg-panel--surface rg-panel__body">
        <h1 id="product-heading" tabindex="-1">Your download is starting</h1>
        <p class="product-lede">
          Didn't start?
          <%!-- The page starts this link once as it opens; a click leaves focus where it is. --%>
          <a id="cloak-installer" href={@installer} download phx-hook=".StartDownload">
            Download it directly
          </a>
        </p>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".StartDownload">
          export default {
            mounted() {
              this.el.click()
            }
          }
        </script>
      </header>

      <ol class="cloak-steps">
        <li>
          <Regent.Structure.panel class="cloak-step rg-panel__body">
            <div class="cloak-step__picture" aria-hidden="true">
              <div class="cloak-window">
                <div class="cloak-window__bar">
                  <span class="cloak-window__lights"><i></i><i></i><i></i></span>
                  <span>Regents Cloak</span>
                </div>
                <div class="cloak-window__body">
                  <span class="cloak-window__item">
                    <.app_icon />
                    <span>Regents Cloak</span>
                  </span>
                  <Regent.Icons.icon name="arrow-right" class="cloak-window__arrow" />
                  <span class="cloak-window__item">
                    <.folder />
                    <span>Applications</span>
                  </span>
                </div>
              </div>
            </div>
            <h2>1. Drag Regents Cloak to Applications</h2>
            <p>
              Open the Regents Cloak disk image from your Downloads folder, then drag Regents Cloak onto the Applications folder.
            </p>
          </Regent.Structure.panel>
        </li>
        <li>
          <Regent.Structure.panel class="cloak-step rg-panel__body">
            <div class="cloak-step__picture cloak-step__picture--menu" aria-hidden="true">
              <div class="cloak-menubar">
                <div class="cloak-menubar__bar">
                  <span class="cloak-menubar__cloak"><.menu_bar_icon /></span>
                  <Regent.Icons.icon name="wifi" />
                  <Regent.Icons.icon name="battery-full" />
                  <Regent.Icons.icon name="search" />
                  <Regent.Icons.icon name="sliders-horizontal" />
                  <span class="cloak-menubar__time">9:41</span>
                </div>
                <span class="cloak-menubar__bubble">Paused</span>
              </div>
            </div>
            <h2>2. Find it in the menu bar</h2>
            <p>
              Open Regents Cloak from Applications. It lives in the menu bar and stays paused until you choose Start.
            </p>
          </Regent.Structure.panel>
        </li>
      </ol>

      <.live_component module={CloakUpdates} id="cloak-updates" client_tag={@client_tag} />
    </section>
    """
  end

  # The 13-block Regents crown, as the design system's flat crown draws it, on a
  # dark Mac icon tile. Cloak's app has no icon of its own yet.
  defp app_icon(assigns) do
    ~H"""
    <svg class="cloak-window__icon" viewBox="0 0 64 64" focusable="false">
      <rect class="cloak-window__tile" x="0.5" y="0.5" width="63" height="63" rx="14" fill="#0A0A0A" />
      <svg x="12" y="20" width="40" height="24" viewBox="31 46 178 106">
        <.crown_blocks fill="#F5F5F2" />
      </svg>
    </svg>
    """
  end

  # Cloak's menu bar icon while paused (`MenuBarIcon.image(.paused)` in the
  # Cloak app): the crown at a ninth of a point per unit, with a pause badge cut
  # clear of its lower trailing corner by a 1-point gap.
  defp menu_bar_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 25 19" focusable="false">
      <defs>
        <mask id="cloak-menubar-gap">
          <rect width="25" height="19" fill="#fff" />
          <circle cx="18" cy="12" r="7" fill="#000" />
        </mask>
        <mask id="cloak-menubar-pause">
          <circle cx="18" cy="12" r="6" fill="#fff" />
          <rect x="15.7" y="9" width="1.8" height="6" rx="0.5" fill="#000" />
          <rect x="18.5" y="9" width="1.8" height="6" rx="0.5" fill="#000" />
        </mask>
      </defs>
      <g mask="url(#cloak-menubar-gap)">
        <svg width="25" height="19" viewBox="31 46 225 171">
          <.crown_blocks fill="currentColor" />
        </svg>
      </g>
      <circle cx="18" cy="12" r="6" fill="currentColor" mask="url(#cloak-menubar-pause)" />
    </svg>
    """
  end

  # The crown's blocks at their origins in the flat crown's 252 by 186 view.
  @crown [{31, 46}, {103, 46}, {175, 46}] ++
           for(y <- [82, 118], x <- [31, 67, 103, 139, 175], do: {x, y})

  attr :fill, :string, required: true

  defp crown_blocks(assigns) do
    assigns = assign(assigns, :blocks, @crown)

    ~H"""
    <g fill={@fill}>
      <rect :for={{x, y} <- @blocks} x={x} y={y} width="34" height="34" />
    </g>
    """
  end

  defp folder(assigns) do
    ~H"""
    <svg class="cloak-window__icon" viewBox="0 0 64 64" focusable="false">
      <path
        class="cloak-folder__back"
        d="M6 14a4 4 0 0 1 4-4h14l6 6h24a4 4 0 0 1 4 4v30a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z"
      />
      <path
        class="cloak-folder__front"
        d="M6 24a4 4 0 0 1 4-4h44a4 4 0 0 1 4 4v26a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z"
      />
      <path
        class="cloak-folder__mark"
        d="M32 28l-9 18M32 28l9 18M26 40h12"
        fill="none"
        stroke-width="3"
        stroke-linecap="round"
      />
    </svg>
    """
  end
end
