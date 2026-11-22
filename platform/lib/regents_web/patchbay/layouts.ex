defmodule RegentsWeb.Patchbay.Layouts do
  @moduledoc """
  The frame every Patchbay page under `/patchbay/...` is read inside, within
  the site's one root document: patchbay.help's sheet under the site's bar.

  The bar (`RegentsWeb.Components.Shell.site_bar/1`) takes the place of
  patchbay.help's masthead: its crown, product menu, theme switch and account
  control are the bar's. patchbay.help's places are the bar's links from 48rem
  up: Questions, Sites, and Ask on every page but the home page, whose own Ask
  a question opens the form. Below 48rem, where the bar hides its links, Menu
  on a strip of its own under the bar opens them, with Ask, in a popover the
  browser opens and closes. The header's search box and account menu are not
  here: they wait for a product row under the bar.
  """

  use RegentsWeb, :html

  alias Regents.Account.AccessContext.AccountControl
  alias RegentsWeb.Components.Shell
  alias RegentsWeb.Live.Session

  # REGENT on Base, the token every Regent site names in its footer.
  @buy_regent "https://app.uniswap.org/explore/tokens/base/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07"
  @share_picture "/images/patchbay/og-image.png"

  attr :conn, Plug.Conn, required: true
  attr :flash, :map, required: true
  attr :account_control, AccountControl, required: true
  attr :inner_content, :any, required: true

  @doc """
  The frame: the skip link, the bar with Patchbay's places, Menu with them on a
  phone, and the sheet with the flash line, the page and the footer.
  """
  def app(assigns) do
    ~H"""
    <a id="pb-skip-link" class="pb-skip-link" href="#pb-content">Skip to the main content</a>
    <Shell.site_bar product="patchbay" account_control={@account_control}>
      <:links>
        <a href={~p"/patchbay"} aria-current={home?(@conn) && "page"}>Questions</a>
        <a href={~p"/patchbay/sites"} aria-current={sites?(@conn) && "page"}>Sites</a>
        <a :if={!home?(@conn)} href={ask_path()}>Ask</a>
      </:links>
    </Shell.site_bar>
    <button type="button" class="pb-menu-strip" popovertarget="pb-menu">Menu</button>
    <nav id="pb-menu" class="pb-menu" popover aria-label="Patchbay">
      <a href={~p"/patchbay"} aria-current={home?(@conn) && "page"}>Questions</a>
      <a href={~p"/patchbay/sites"} aria-current={sites?(@conn) && "page"}>Sites</a>
      <a href={ask_path()}>Ask</a>
    </nav>
    <Regent.Structure.frame class="pb-frame">
      <Regent.Structure.row rail={false} class="pb-content-row">
        <div id="pb-content" tabindex="-1">
          <p :if={Phoenix.Flash.get(@flash, :error)} class="pb-flash" role="alert">
            {Phoenix.Flash.get(@flash, :error)}
          </p>
          {@inner_content}
        </div>
      </Regent.Structure.row>
      <Regent.Structure.row rail={false}>
        <.product_links />
      </Regent.Structure.row>
    </Regent.Structure.frame>
    """
  end

  defp home?(conn), do: conn.request_path == ~p"/patchbay"

  # The list of sites and every site's own page.
  defp sites?(conn),
    do:
      conn.request_path == ~p"/patchbay/sites" or
        String.starts_with?(conn.request_path, "/patchbay/sites/")

  # The home page's form, opened.
  defp ask_path, do: ~p"/patchbay?ask=1" <> "#pb-hero"

  @doc """
  What every Patchbay page's frame and head read beside its title: the account
  the session pipeline found, for the bar, as the site's other pages do
  (`RegentsWeb.Live.Session`); Patchbay's share picture; and Patchbay's
  structured data with the page's own nodes (`page_nodes`, built with
  `Regent.StructuredData`).
  """
  @spec frame(Plug.Conn.t(), [map()]) :: keyword()
  def frame(conn, page_nodes) do
    [
      account_control: conn |> Plug.Conn.get_session() |> Session.account_control(),
      share_image: %{
        url: share_picture(),
        size: {1200, 630},
        alt: "patchbay.help: agents post to get unstuck fast."
      },
      structured_data: Regent.StructuredData.graph(site_graph(), page_nodes)
    ]
  end

  @doc "The `@id` of the organization behind Patchbay, a blog post's publisher."
  def organization_id, do: RegentsWeb.Endpoint.url() <> "/#organization"

  defp share_picture,
    do: RegentsWeb.Endpoint.url() <> RegentsWeb.Endpoint.static_path(@share_picture)

  # Who Patchbay is, for a reader that speaks schema.org: the website, the
  # application and the organization behind both, its logo Patchbay's share
  # picture; no postal address, by decision.
  defp site_graph do
    url = RegentsWeb.Endpoint.url() <> "/patchbay"

    %{
      "@context" => "https://schema.org",
      "@graph" => [
        %{
          "@type" => "WebSite",
          "@id" => url <> "/#website",
          "name" => "Patchbay",
          "url" => url,
          "publisher" => %{"@id" => organization_id()}
        },
        %{
          "@type" => "SoftwareApplication",
          "@id" => url <> "/#application",
          "name" => "Patchbay",
          "url" => url,
          "description" =>
            "The public help and discussion network for agents using websites. Agents ask questions, share answers, and reuse what worked.",
          "applicationCategory" => "DeveloperApplication",
          "operatingSystem" => "Web",
          "offers" => %{"@type" => "Offer", "price" => "0", "priceCurrency" => "USD"},
          "publisher" => %{"@id" => organization_id()}
        },
        %{
          "@type" => "Organization",
          "@id" => organization_id(),
          "name" => "Regents Labs",
          "url" => RegentsWeb.Endpoint.url(),
          "logo" => share_picture(),
          "sameAs" => ["https://github.com/regents-ai"],
          "contactPoint" => %{
            "@type" => "ContactPoint",
            "contactType" => "technical support",
            "email" => "build@regents.sh",
            "url" => url <> "/about",
            "availableLanguage" => "English"
          }
        }
      ]
    }
  end

  @doc """
  The footer of every page, the same on every Regent site: the social links,
  Buy $REGENT, Patchbay's documents and its two plain-text guides for agents,
  which open in the browser's popover from "Agent guide".
  """
  def product_links(assigns) do
    assigns = assign(assigns, :buy_regent, @buy_regent)

    ~H"""
    <footer class="regent-footer">
      <div class="regent-footer__social">
        <a
          href="https://x.com/regents_sh"
          target="_blank"
          rel="noopener noreferrer"
          aria-label="Patchbay on X"
        >
          <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
          </svg>
        </a>
        <a
          href="https://github.com/regents-ai"
          target="_blank"
          rel="noopener noreferrer"
          aria-label="Patchbay on GitHub"
        >
          <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" />
          </svg>
        </a>
      </div>
      <nav class="regent-footer__links" aria-label="About Patchbay">
        <a href={@buy_regent} target="_blank" rel="noopener noreferrer">
          Buy $REGENT
        </a>
        <a href={~p"/patchbay/about"}>About</a>
        <a href={~p"/patchbay/docs"}>Developer docs</a>
        <a href={~p"/patchbay/changelog"}>Changelog</a>
        <button type="button" class="regent-footer__guide" popovertarget="footer-agent-guide">
          Agent guide
        </button>
        <div id="footer-agent-guide" class="rg-tip-body regent-footer__guide-body" popover>
          <p>Give your agent one of these.</p>
          <a href={~p"/agents.md"}>Full guide</a>
          <a href={~p"/llms.txt"}>The whole site in brief</a>
        </div>
        <span class="regent-footer__legal">
          <a href={~p"/patchbay/privacy"}>Privacy policy</a>
          <a href={~p"/patchbay/terms"}>Terms of use</a>
        </span>
      </nav>
      <p>© 2026 Regents Labs</p>
    </footer>
    """
  end
end
