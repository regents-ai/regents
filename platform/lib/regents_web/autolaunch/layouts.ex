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

  `app/1` is the layout of the scope's controller pages and of its live pages;
  `on_mount(:page, ...)` gives each live page the address the links mark.
  """

  use RegentsWeb, :html

  alias Regents.Account.AccessContext.AccountControl
  alias Regents.Account.Accounts
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
    <Shell.site_bar
      product="autolaunch"
      account_control={@account_control}
      current_path={@current_path}
    >
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
      :if={!Shell.workspace?(@current_path)}
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
    <.drawer :if={!Shell.workspace?(@current_path)} links={links()} current_path={@current_path} />
    <Regent.Primitives.button
      variant="quiet"
      type="button"
      class="shell-menu-scrim"
      :if={!Shell.workspace?(@current_path)}
      data-shell-menu-scrim
      aria-label="Close navigation"
      tabindex="-1"
    ></Regent.Primitives.button>
    """
  end

  @doc "Each live page's address and client tag, for links and rate-limited page reads."
  def on_mount(:page, _params, session, socket) do
    {:cont,
     socket
     |> assign(:client_key, session["client_tag"] || "anonymous")
     |> Phoenix.LiveView.attach_hook(:page, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :current_path, URI.parse(uri).path)}
     end)
     |> Phoenix.LiveView.attach_hook(:linked_identities, :handle_info, fn
       {:watch_linked_identities, module, id}, socket ->
         {:halt, watch_linked_identities(socket, module, id)}

       {:linked_identities_changed, _account_id, _provider}, socket ->
         case linked_identity_watchers(socket) do
           [] ->
             {:cont, socket}

           watchers ->
             for {module, id} <- watchers do
               Phoenix.LiveView.send_update(module, id: id, refresh_x: true)
             end

             {:halt, socket}
         end

       _other, socket ->
         {:cont, socket}
     end)}
  end

  defp watch_linked_identities(socket, module, id) do
    watchers = MapSet.put(socket.private[:linked_identity_watchers] || MapSet.new(), {module, id})

    socket =
      if socket.private[:linked_identities_subscribed?] do
        socket
      else
        case {Phoenix.LiveView.connected?(socket), socket.assigns[:access_context]} do
          {true, %{principal: {:human, %{id: account_id}}}} when is_integer(account_id) ->
            Accounts.subscribe_linked_identities(account_id)
            Phoenix.LiveView.put_private(socket, :linked_identities_subscribed?, true)

          _other ->
            socket
        end
      end

    Phoenix.LiveView.put_private(socket, :linked_identity_watchers, watchers)
  end

  defp linked_identity_watchers(socket) do
    case socket.private[:linked_identity_watchers] do
      %MapSet{} = watchers -> MapSet.to_list(watchers)
      _none -> []
    end
  end

  # Autolaunch's own destinations, in autolaunch.sh's order.
  defp links do
    [
      %{label: "Explore", path: ~p"/autolaunch/app"},
      %{label: "Auctions", path: ~p"/autolaunch/auctions"},
      %{label: "Tokens", path: ~p"/autolaunch/tokens"},
      %{label: "Portfolio", path: ~p"/autolaunch/portfolio"},
      %{label: "Create", path: ~p"/autolaunch/create"}
    ] ++
      if(Regents.Autolaunch.Earn.Catalog.enabled?(),
        do: [%{label: "Earn", path: ~p"/autolaunch/earn"}],
        else: []
      )
  end

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
  $REGENT, About, the two plain-text guides for agents, which open in the
  browser's popover from "Agent guide", and the Changelog; then the two legal
  documents and the copyright.
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
        <a href={~p"/autolaunch/about"}>About</a>
        <span class="rg-tip">
          <button
            id="footer-agent-guide-trigger"
            type="button"
            class="regent-footer__guide"
            popovertarget="footer-agent-guide"
            aria-controls="footer-agent-guide"
            aria-haspopup="true"
          >
            Agent guide
          </button>
          <div
            id="footer-agent-guide"
            class="rg-tip-body regent-footer__guide-body"
            popover
            phx-update="ignore"
          >
            <p>Give your agent one of these.</p>
            <a href={~p"/autolaunch/docs"}>Autolaunch developer guide</a>
            <a href={~p"/agents.md"}>What agents can do here</a>
            <a href={~p"/llms.txt"}>The whole site in brief</a>
          </div>
        </span>
        <a href={~p"/autolaunch/changelog"}>Changelog</a>
        <span class="regent-footer__legal">
          <a href={~p"/autolaunch/privacy"}>Privacy policy</a>
          <a href={~p"/autolaunch/terms"}>Terms of use</a>
        </span>
      </nav>
      <p class="regent-footer__copyright">© 2026 Regents Labs</p>
    </footer>
    """
  end
end
