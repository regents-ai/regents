defmodule RegentsWeb.Autolaunch.Layouts do
  @moduledoc """
  The frame every Autolaunch page under `/autolaunch/...` is read inside, within
  the site's one root document: autolaunch.sh's page shell under the site's bar.

  The bar (`RegentsWeb.Components.Shell.site_bar/1`) holds Autolaunch's own
  links from 48rem up. On a phone they are in the drawer behind Menu, on a strip
  of its own directly under the bar; the browser opens and closes it
  (`assets/js/autolaunch/shell_menu.ts`), so the server always draws it closed.
  The page column holds the Learn links on a Learn page, the page, and the
  footer.

  The parts of autolaunch.sh's header that need what is not here yet are not
  drawn: the market ticker, the $REGENT menu, search, and the account menu with
  its agents and Pair New Agent; signed in, the bar shows the person's picture,
  name and Sign out, as on Techtree. Each comes back as its own part beside the
  bar.
  """

  use RegentsWeb, :html

  alias Regents.Account.AccessContext.AccountControl
  alias RegentsWeb.Autolaunch.Components.LearnNavigation
  alias RegentsWeb.Autolaunch.Components.RegentLinks
  alias RegentsWeb.Components.Shell

  # REGENT on Base, the token every Regent site names in its footer.
  @buy_regent "https://app.uniswap.org/explore/tokens/base/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07"

  attr :current_path, :string, required: true
  attr :account_control, AccountControl, required: true
  attr :inner_content, :any, required: true

  @doc """
  The frame: the skip link, the bar with Autolaunch's links, Menu, the page
  column with the page and the footer, and the phone drawer with the dimmed page
  beside it. While the drawer is open the page and the footer are inert.
  """
  def app(assigns) do
    ~H"""
    <a class="shell-skip" href="#shell-content">Skip to content</a>
    <Shell.site_bar product="autolaunch" account_control={@account_control}>
      <:links>
        <a
          :for={link <- links()}
          href={link.path}
          aria-current={@current_path == link.path && "page"}
        >
          {link.label}
        </a>
      </:links>
    </Shell.site_bar>
    <Regent.Primitives.button
      variant="quiet"
      id="mobile-menu-button"
      class="mobile-menu-button"
      type="button"
      aria-controls="shell-drawer"
      aria-expanded="false"
    >
      Menu
    </Regent.Primitives.button>
    <Regent.Structure.frame class="shell">
      <Regent.Structure.row class="shell-body" rail={false}>
        <div class="shell-main">
          <main id="shell-content" class="shell-content" tabindex="-1" data-shell-behind-menu>
            <LearnNavigation.navigation current_path={@current_path} />
            {@inner_content}
          </main>
          <.product_links id="shell-footer" data-shell-behind-menu />
        </div>
      </Regent.Structure.row>
    </Regent.Structure.frame>
    <.drawer links={links()} current_path={@current_path} />
    <Regent.Primitives.button
      variant="quiet"
      type="button"
      class="shell-menu-scrim"
      data-shell-menu-scrim
      aria-label="Close navigation"
      tabindex="-1"
    ></Regent.Primitives.button>
    """
  end

  # Autolaunch's own destinations, in autolaunch.sh's order, each once its page is
  # here. Explore is the home page and marks only itself.
  defp links, do: [%{label: "Explore", path: ~p"/autolaunch"}]

  attr :links, :list, required: true
  attr :current_path, :string, required: true

  # Autolaunch's links as plain rows, from the left edge under the bar and Menu;
  # its Close navigation bar is its first row.
  defp drawer(assigns) do
    ~H"""
    <div id="shell-drawer" tabindex="-1">
      <Regent.Primitives.button
        variant="quiet"
        type="button"
        class="shell-menu-close"
        data-shell-menu-close
      >
        Close navigation
      </Regent.Primitives.button>
      <nav class="shell-drawer__nav" aria-label="Site">
        <ul>
          <li :for={link <- @links}>
            <a
              href={link.path}
              class="shell-drawer__row"
              aria-current={@current_path == link.path && "page"}
            >
              {link.label}
            </a>
          </li>
        </ul>
      </nav>
    </div>
    """
  end

  attr :rest, :global

  @doc """
  The footer of every page: the social links on its first row; below them Buy
  $REGENT, the two plain-text guides for agents, which open in the browser's
  popover from "Agent guide", and the Changelog; then the two legal documents
  and the copyright.
  """
  def product_links(assigns) do
    assigns = assign(assigns, :buy_regent, @buy_regent)

    ~H"""
    <footer class="regent-footer" {@rest}>
      <div class="regent-footer__buttons">
        <RegentLinks.social_links />
      </div>
      <nav class="regent-footer__links" aria-label="About Autolaunch">
        <a href={@buy_regent} target="_blank" rel="noopener noreferrer">Buy $REGENT</a>
        <span class="rg-tip">
          <button type="button" class="regent-footer__guide" popovertarget="footer-agent-guide">
            Agent guide
          </button>
          <div id="footer-agent-guide" class="rg-tip-body regent-footer__guide-body" popover>
            <p>Give your agent one of these.</p>
            <a href={~p"/agents.md"}>What agents can do here</a>
            <a href={~p"/llms.txt"}>The whole site in brief</a>
          </div>
        </span>
        <a href={~p"/autolaunch/changelog"}>Changelog</a>
        <span class="regent-footer__legal">
          <a href={~p"/privacy"}>Privacy policy</a>
          <a href={~p"/terms"}>Terms of use</a>
        </span>
      </nav>
      <p class="regent-footer__copyright">© 2026 Regents Labs</p>
    </footer>
    """
  end
end
