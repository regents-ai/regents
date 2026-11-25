defmodule RegentsWeb.Patchbay.Layouts do
  @moduledoc "The shared workspace navigation, page and footer for Patchbay."

  use RegentsWeb, :html

  alias Regents.Account.AccessContext.AccountControl
  alias Regents.Patchbay.Forum.ProductBoards
  alias RegentsWeb.Components.Shell
  alias RegentsWeb.Live.Session

  # REGENT on Base, the token every Regent site names in its footer.
  @buy_regent "https://app.uniswap.org/explore/tokens/base/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07"
  @share_picture "/images/patchbay/og-image.png"

  @doc """
  Assigns `:current_path` on every Patchbay LiveView route so `Shell.site_bar`
  highlights active navigation links on LiveView pages just like controller pages.
  """
  def on_mount(:page, _params, _session, socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(socket, :patchbay_page_path, :handle_params, fn
       _params, uri, socket ->
         {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(uri).path)}
     end)}
  end

  attr :conn, Plug.Conn, default: nil
  attr :current_path, :string, default: nil
  attr :flash, :map, required: true
  attr :account_control, AccountControl, required: true
  attr :current_profile, :map, default: nil
  attr :inner_content, :any, required: true

  @doc """
  The skip link, workspace navigation, flash, page and footer.
  """
  def app(assigns) do
    path = active_path(assigns)

    profile_path = profile_path(assigns[:current_profile])

    assigns =
      assign(assigns,
        active_path: path,
        sidebar_section: sidebar_section(path, assigns[:conn]),
        sidebar_links: if(profile_path, do: [{"Profile", profile_path}], else: [])
      )

    ~H"""
    <a id="pb-skip-link" class="pb-skip-link" href="#pb-content">Skip to the main content</a>
    <Shell.site_bar
      product="patchbay"
      account_control={@account_control}
      current_path={@active_path}
      sidebar_section={@sidebar_section}
      sidebar_links={@sidebar_links}
    />
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

  defp active_path(%{current_path: path}) when is_binary(path), do: path
  defp active_path(%{conn: %Plug.Conn{request_path: path}}), do: path
  defp active_path(_assigns), do: nil

  defp sidebar_section(_path, %Plug.Conn{path_params: %{"host" => _host}}),
    do: ~p"/patchbay/sites"

  defp sidebar_section(path, _conn) when is_binary(path) do
    cond do
      String.starts_with?(path, ["/patchbay/posts/", "/patchbay/reports/", "/patchbay/discuss/"]) ->
        ~p"/patchbay/forum"

      Enum.any?(ProductBoards.all(), &(&1.path == path)) ->
        ~p"/patchbay/forum"

      true ->
        nil
    end
  end

  defp sidebar_section(_path, _conn), do: nil

  defp profile_path(%{public_id: public_id}) when is_binary(public_id) and public_id != "",
    do: ~p"/patchbay/agents/#{public_id}"

  defp profile_path(_), do: nil

  @doc """
  What every Patchbay page's frame and head read beside its title: the account
  the session pipeline found, for the bar, as the site's other pages do
  (`RegentsWeb.Live.Session`); that the page also answers as Markdown, as
  every Patchbay page does; Patchbay's share picture; and Patchbay's
  structured data with the page's own nodes (`page_nodes`, built with
  `Regent.StructuredData`).
  """
  @spec frame(Plug.Conn.t(), [map()]) :: keyword()
  def frame(conn, page_nodes) do
    [
      account_control: conn |> Plug.Conn.get_session() |> Session.account_control(),
      markdown?: true,
      share_image: %{
        url: share_picture(),
        size: {1200, 630},
        alt:
          "Patchbay on regents.sh: live agentic commerce support, HTTP 402 diagnostics, and cybersecurity triage."
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
            "Live support, HTTP 402 protocol diagnostics, and cybersecurity terminal for AI agents participating in agentic commerce (x402, MPP / Tempo) and active critical CVE defense (cve.now).",
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
          <a href={~p"/patchbay/skill.md"}>Patchbay skill.md</a>
          <a href={~p"/patchbay/llms.txt"}>Patchbay llms.txt</a>
          <a href={~p"/agents.md"}>Regents full guide</a>
          <a href={~p"/llms.txt"}>Regents llms.txt</a>
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
