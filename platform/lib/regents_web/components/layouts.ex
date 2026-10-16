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

  attr :theme_toggle, :boolean,
    default: true,
    doc: "false on the home page, which is always dark"

  attr :agent_tools, :boolean,
    default: false,
    doc: "true in the app, which has no bottom bar to hold the tools button"

  @doc """
  The footer of the home page, every public page and the app's pages, the same
  on every Regent site: the social links, Buy $REGENT and the site's documents.
  Below a public page it sits at the foot of the screen however short the page is.
  """
  def product_links(assigns) do
    ~H"""
    <footer class="regent-footer">
      <div class="regent-footer__social">
        <RegentsWeb.Components.RegentLinks.social_links />
        <RegentsWeb.Components.Shell.theme_toggle :if={@theme_toggle} id="footer-theme-control" />
        <RegentsWeb.Components.AgentTools.button
          :if={@agent_tools}
          id="shell-agent-tools-button"
          dialog="shell-agent-tools"
        />
      </div>
      <nav class="regent-footer__links" aria-label="About Regents Labs">
        <a href={RegentsWeb.TokenLinks.buy()} target="_blank" rel="noopener noreferrer">
          Buy $REGENT
        </a>
        <a href={~p"/docs"}>Docs</a>
        <a href={~p"/about"}>About</a>
        <a href={~p"/contact"}>Contact</a>
        <a href={~p"/privacy"}>Privacy</a>
        <a href={~p"/terms"}>Terms</a>
      </nav>
      <p>© 2026 Regents Labs</p>
    </footer>
    """
  end
end
