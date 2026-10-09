defmodule RegentsWeb.Layouts do
  @moduledoc "Root document layout for the public page and persistent shell."

  use RegentsWeb, :html

  embed_templates("layouts/*")

  attr(:flash, :map, required: true)
  attr(:inner_content, :any, required: true)

  def app(assigns) do
    ~H"""
    {@inner_content}
    <div id="flash-region" aria-live="polite">
      <Regent.Primitives.notice :if={message = Phoenix.Flash.get(@flash, :info)}>
        {message}
      </Regent.Primitives.notice>
      <Regent.Primitives.notice :if={message = Phoenix.Flash.get(@flash, :error)} tone="error">
        {message}
      </Regent.Primitives.notice>
    </div>
    """
  end

  @doc "Product and source discovery without loading a browser integration."
  def product_links(assigns) do
    ~H"""
    <footer aria-label="Project links" class="product-links">
      <RegentsWeb.Components.Shell.theme_toggle id="footer-theme-control" />
      <div class="rl-header-links">
        <RegentsWeb.Components.RegentLinks.header_links id="footer-token-menu" />
      </div>
      <a href="/llms.txt">For agents</a>
      <.apps_menu />
    </footer>
    """
  end

  # The Regents Labs apps, each shown with the crown in its own pair of brand
  # colours. The other sites open in a new tab; this site's own pages do not.
  @regents_apps [
    %{name: "Patchbay", href: "https://patchbay.help", tone: "patchbay", away?: true},
    %{name: "Autolaunch", href: "https://autolaunch.sh", tone: "autolaunch", away?: true},
    %{name: "Keyfleet", href: "https://keyfleet.ai", tone: "keyfleet", away?: true},
    %{name: "Techtree", href: "https://techtree.sh", tone: "techtree", away?: true},
    %{name: "Protocol", href: "/stake", tone: "protocol", away?: false},
    %{name: "Account", href: "/account", tone: "account", away?: false}
  ]

  # The browser opens and closes the panel itself (`popover`), so it closes on
  # Escape or a press anywhere else, and a page update never shuts it. It opens
  # above the button, since the footer ends the page.
  defp apps_menu(assigns) do
    assigns = assign(assigns, :apps, @regents_apps)

    ~H"""
    <button
      id="footer-apps-button"
      class="product-links__apps-button"
      type="button"
      popovertarget="footer-apps"
      aria-label="Regents apps"
    >
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <rect :for={{x, y} <- nine_dots()} x={x} y={y} width="4.5" height="4.5" />
      </svg>
    </button>
    <nav id="footer-apps" class="product-links__apps" popover aria-labelledby="footer-apps-title">
      <h2 id="footer-apps-title">Regents Labs apps</h2>
      <ul>
        <li :for={app <- @apps}>
          <a href={app.href} target={app.away? && "_blank"} rel={app.away? && "noopener"}>
            <span class="product-links__apps-tile" data-tone={app.tone}>
              <RegentsWeb.Components.RegentLinks.source_icon kind={:regent} />
            </span>
            <span>{app.name}</span>
          </a>
        </li>
      </ul>
    </nav>
    """
  end

  defp nine_dots, do: for(y <- [1.5, 9.75, 18], x <- [1.5, 9.75, 18], do: {x, y})
end
