defmodule RegentsWeb.Autolaunch.Layouts do
  @moduledoc "Autolaunch's shared navigation, page and footer."

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
  The skip link, shared navigation, page and footer.
  """
  def app(assigns) do
    ~H"""
    <a class="shell-skip" href="#shell-content">Skip to content</a>
    <Shell.site_bar
      product="autolaunch"
      account_control={@account_control}
      current_path={@current_path}
    />
    <Regent.Structure.frame class="shell">
      <Regent.Structure.row class="shell-body" rail={false}>
        <div class="shell-main">
          <main id="shell-content" class="shell-content" tabindex="-1">
            <LearnNavigation.navigation current_path={@current_path} />
            {@inner_content}
          </main>
          <.product_links id="shell-footer" />
        </div>
      </Regent.Structure.row>
    </Regent.Structure.frame>
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
