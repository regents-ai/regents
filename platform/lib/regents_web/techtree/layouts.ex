defmodule RegentsWeb.Techtree.Layouts do
  @moduledoc """
  The frame every Techtree page is read inside, within the site's one root
  document. The site's bar (`RegentsWeb.Components.Shell.site_bar/1`) holds
  Techtree's links, Services, Results and Docs (`RegentsWeb.Techtree.SiteMenu`),
  the theme switch and the site's account control. Signed in, the account control
  is the person's picture and name with Sign out, as the site draws it where there
  is no account menu. The footer lists the services, the site's pages and the
  agent links in columns, with the legal pages.

  `app/1` is the layout of the Techtree scope's pages; `on_mount(:page, ...)`
  gives each live page the address the bar marks and the description the
  root document carries.
  """

  use RegentsWeb, :html

  alias Regents.Account.AccessContext.AccountControl
  alias RegentsWeb.Components.Shell
  alias RegentsWeb.Techtree.DocsGuides
  alias RegentsWeb.Techtree.Services
  alias RegentsWeb.Techtree.SiteMenu

  attr :current_path, :string, required: true
  attr :account_control, AccountControl, required: true
  attr :inner_content, :any, required: true

  @doc "The frame: the skip link, the bar and the page under it."
  def app(assigns) do
    ~H"""
    <a class="skip-link" href="#main-content">
      Skip to main content
    </a>
    <.bar current_path={@current_path} account_control={@account_control} />
    <Regent.Structure.frame class="techtree-frame">
      {@inner_content}
    </Regent.Structure.frame>
    """
  end

  @doc """
  Each live page's address, for the bar's current link, and its
  description, for the root document's head, as the router hands it over.
  """
  def on_mount(:page, _params, _session, socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(socket, :page, :handle_params, fn _params, uri, socket ->
       path = URI.parse(uri).path
       {:cont, assign(socket, current_path: path, page_description: description(path))}
     end)}
  end

  @doc """
  Wrap one page.
  """
  attr(:wide, :boolean, default: false, doc: "give the page the wider measure")
  attr(:flush, :boolean, default: false, doc: "let a page own its vertical rhythm")
  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <Regent.Structure.row rail={false}>
      <main id="main-content" class={["page", @wide && "page--wide", @flush && "page--flush"]}>
        {render_slot(@inner_block)}
      </main>
    </Regent.Structure.row>

    <.product_links />
    """
  end

  attr(:current_path, :string, required: true)
  attr(:account_control, AccountControl, required: true)

  # Services goes to the services on Techtree's home page, and is current on a
  # service's own page.
  defp bar(assigns) do
    assigns = assign(assigns, links: SiteMenu.links())

    ~H"""
    <Shell.site_bar product="techtree" account_control={@account_control}>
      <:links>
        <a
          href={~p"/techtree" <> "#services"}
          aria-current={String.starts_with?(@current_path, "/techtree/services/") && "page"}
        >
          Services
        </a>
        <a
          :for={link <- @links}
          href={link.href}
          aria-current={current?(link.href, @current_path) && "page"}
        >
          {link.name}
        </a>
      </:links>
    </Shell.site_bar>
    """
  end

  # A link is the page's own when the page is it or sits under it.
  defp current?(href, path), do: path == href or String.starts_with?(path, href <> "/")

  attr :class, :string, required: true

  # Techtree's mark: thirteen squares, the canopy of a tree.
  defp mark(assigns) do
    ~H"""
    <span class={@class} aria-hidden="true">
      <svg
        viewBox="0 0 58 34"
        xmlns="http://www.w3.org/2000/svg"
        fill="currentColor"
        aria-hidden="true"
      >
        <rect x="0" y="0" width="10" height="10" />
        <rect x="24" y="0" width="10" height="10" />
        <rect x="48" y="0" width="10" height="10" />
        <rect x="0" y="12" width="10" height="10" />
        <rect x="12" y="12" width="10" height="10" />
        <rect x="24" y="12" width="10" height="10" />
        <rect x="36" y="12" width="10" height="10" />
        <rect x="48" y="12" width="10" height="10" />
        <rect x="0" y="24" width="10" height="10" />
        <rect x="12" y="24" width="10" height="10" />
        <rect x="24" y="24" width="10" height="10" />
        <rect x="36" y="24" width="10" height="10" />
        <rect x="48" y="24" width="10" height="10" />
      </svg>
    </span>
    """
  end

  @doc "The search description of the Techtree page at `path`."
  @spec description(String.t()) :: String.t()
  def description("/techtree/results"),
    do: "Browse published Results: the same agent on the same tasks, with and without a Skill."

  def description("/techtree/results/" <> _digest),
    do: "Inspect one published Techtree Result and its task-level evidence."

  def description("/techtree/climbs/" <> _slug),
    do: "Inspect the fixed task contract for a published Techtree Climb."

  def description("/techtree/services/security/sample-report"),
    do:
      "A sample security review: one validated finding on the Agent Wallet Bench, fixed, verified and released."

  def description("/techtree/services/" <> _service = path) do
    %{promise: promise} =
      Enum.find(Services.all() ++ Services.others(), &(Services.path(&1.id) == path))

    promise
  end

  def description("/techtree/formal"),
    do:
      "Techtree Formal: what formal verification proves and what it doesn't, recent advances with their sources, and how to send code to be proved."

  def description("/techtree/changelog"),
    do: "Techtree release notes: new features, fixes, and the limits of each release."

  def description("/techtree/train/" <> _slug),
    do:
      "A public Skill against the revision chosen to improve it, on a final test: attempts solved, the verdict, every case, the method and the tools."

  def description("/techtree/docs"),
    do: "Run Techtree locally, check and publish a Result, and connect an agent."

  def description("/techtree/docs/" <> slug) do
    case DocsGuides.fetch(slug) do
      {:ok, guide} -> guide.summary
      :error -> raise RegentsWeb.NotFoundError, "there is no Docs guide by that name"
    end
  end

  def description(path) when path in ["/techtree", "/techtree/examples/tdd"],
    do:
      "Custom Skills, evaluations, training environments, and open-weight models, built around your workflows, with results you can measure."

  @doc """
  The footer under every page: the services, the site's pages, $REGENT and the
  files to hand an agent in columns (`RegentsWeb.Techtree.SiteMenu`), the legal pages
  and the brand links.
  """
  def product_links(assigns) do
    assigns = assign(assigns, :columns, SiteMenu.footer())

    ~H"""
    <Regent.Structure.row rail={false}>
      <footer class="regent-footer">
        <div class="regent-footer__top">
          <div class="regent-footer__brand">
            <a class="regent-footer__name" href={~p"/techtree"}>
              <.mark class="regent-footer__mark" /> Techtree
            </a>
            <p class="regent-footer__line">Open-source tools. Paid custom projects.</p>
            <div class="regent-footer__social">
              <a
                href="https://x.com/regents_sh"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="Techtree on X"
              >
                <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                </svg>
              </a>
              <a
                href="https://github.com/regents-ai"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="Techtree on GitHub"
              >
                <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" />
                </svg>
              </a>
            </div>
          </div>
          <nav class="regent-footer__columns" aria-label="Site">
            <div :for={column <- @columns} class="regent-footer__column">
              <p class="regent-footer__title" id={"footer-#{column.id}"}>{column.title}</p>
              <ul aria-labelledby={"footer-#{column.id}"}>
                <li :for={page <- column.pages}>
                  <a
                    href={page.href}
                    target={external?(page.href) && "_blank"}
                    rel={external?(page.href) && "noopener noreferrer"}
                  >
                    {page.name}
                  </a>
                </li>
              </ul>
            </div>
          </nav>
        </div>
        <div class="regent-footer__base">
          <p>© 2026 Regents Labs</p>
          <nav class="regent-footer__legal" aria-label="Legal">
            <a href={~p"/privacy"}>Privacy policy</a>
            <a href={~p"/terms"}>Terms of use</a>
          </nav>
        </div>
        <div class="regent-footer__giant" aria-hidden="true">Techtree</div>
      </footer>
    </Regent.Structure.row>
    """
  end

  defp external?(href), do: String.starts_with?(href, "https://")
end
