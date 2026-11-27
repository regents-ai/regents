defmodule RegentsWeb.Router do
  use RegentsWeb, :router
  use ErrorTracker.Web, :router

  alias RegentsWeb.ContentSecurityPolicy

  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :browser do
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug RegentsWeb.Plugs.RequireArticleAdmin
    plug RegentsWeb.Plugs.Theme
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
    plug :put_product, "regents"
    plug :put_current_path
    plug RegentsWeb.Plugs.LaunchGate
    plug :accepts, ["html"]
    plug :protect_from_forgery

    # These pages can start wallet sign-in.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.sign_in()
    }
  end

  # Patchbay's pages: the browser pipeline, also answering Markdown, so a Patchbay
  # page asked for as Markdown is answered by its own controller, as on
  # patchbay.help, and a missing record answers 404.
  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :patchbay_browser do
    plug :accepts, ["html", "md"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug RegentsWeb.Plugs.RequireArticleAdmin
    plug RegentsWeb.Plugs.Theme
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
    plug :put_product, "regents"
    plug :put_current_path
    plug RegentsWeb.Plugs.LaunchGate
    plug :protect_from_forgery

    # These pages can start wallet sign-in.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.sign_in()
    }

    plug RegentsWeb.Patchbay.Plugs.ForumSession, issue: true
    plug RegentsWeb.Patchbay.Plugs.CurrentProfile
  end

  pipeline :patchbay_paired_agent do
    plug RegentsWeb.Plugs.ReadOnly
    plug :put_site_edition, :main
    plug RegentsWeb.Patchbay.Plugs.SignedBudget
    plug RegentsWeb.Patchbay.Plugs.PairedAgent
  end

  pipeline :patchbay_wallet_author do
    plug RegentsWeb.Plugs.ReadOnly
    plug :put_site_edition, :main
    plug RegentsWeb.Patchbay.Plugs.SignedBudget
    plug RegentsWeb.Patchbay.Plugs.WalletAuthor
  end

  pipeline :patchbay_agent_payment_admission do
    plug RegentsWeb.Patchbay.Plugs.AgentPaymentAdmission
  end

  pipeline :patchbay_payment_budget do
    plug RegentsWeb.Patchbay.Plugs.PaymentBudget
  end

  pipeline :patchbay_hello_proof do
    plug RegentsWeb.Plugs.ReadOnly
    plug RegentsWeb.Patchbay.Plugs.SignedBudget
    plug RegentsWeb.Patchbay.Plugs.HelloProof
  end

  pipeline :patchbay_siwa_test do
    plug :put_format, "json"
    plug RegentsWeb.Plugs.LaunchGate
    plug RegentsWeb.Plugs.ReadOnly
    plug RegentsWeb.Patchbay.Plugs.SignedBudget
    plug RegentsWeb.Patchbay.Plugs.SiwaTestProof
  end

  pipeline :patchbay_x402_test do
    plug :accepts, ["json"]
    plug RegentsWeb.Plugs.LaunchGate
    plug RegentsWeb.Plugs.ReadOnly
    plug RegentsWeb.Patchbay.Plugs.X402Test
  end

  # sobelow_skip ["Config.CSP"]
  pipeline :patchbay_forum_tools do
    plug :accepts, ["json"]
    plug RegentsWeb.Plugs.LaunchGate
    plug RegentsWeb.Plugs.ReadOnly
    plug :put_site_edition, :main
    plug :fetch_session
    plug :enforce_session_authority
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug RegentsWeb.Patchbay.Plugs.ForumSession
    plug RegentsWeb.Patchbay.Plugs.CurrentProfile
  end

  pipeline :patchbay_api do
    plug :accepts, ["json"]
    plug RegentsWeb.Plugs.LaunchGate
    plug :put_site_edition, :main
  end

  pipeline :patchbay_public do
    plug RegentsWeb.Plugs.LaunchGate
    plug :put_site_edition, :main
  end

  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :patchbay_html_or_json do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug RegentsWeb.Plugs.RequireArticleAdmin
    plug RegentsWeb.Plugs.Theme
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
    plug :put_product, "patchbay"
    plug :put_current_path
    plug :put_site_edition, :main
    plug :put_layout, html: {RegentsWeb.Patchbay.Layouts, :app}
    plug RegentsWeb.Plugs.LaunchGate
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.sign_in()
    }

    plug RegentsWeb.Patchbay.Plugs.ForumSession, issue: true
    plug RegentsWeb.Patchbay.Plugs.CurrentProfile
  end

  pipeline :patchbay_require_profile do
    plug RegentsWeb.Patchbay.Plugs.RequireProfile
  end

  pipeline :patchbay_payments do
    plug RegentsWeb.Patchbay.Plugs.ForumSession, issue: true
  end

  pipeline :patchbay_offers do
    plug RegentsWeb.Patchbay.OffersGate
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug RegentsWeb.Plugs.LaunchGate
  end

  # Where the site only reads, no agent is paired here, so a signed request is
  # refused plainly before the sign-in service is asked.
  pipeline :paired_agent do
    plug RegentsWeb.Plugs.ReadOnly
    plug RegentsWeb.Account.PairedAgent
  end

  pipeline :human_api do
    plug :fetch_session
    plug :enforce_session_authority
    plug :protect_from_forgery
    plug :private_response
  end

  # Signing in, agents' own requests and signed-in reads, refused plainly where
  # the site only reads (`Regents.read_only?/0`).
  pipeline :read_only do
    plug RegentsWeb.Plugs.ReadOnly
  end

  # The profile API's owner: the person signed in here, with the forms token on a
  # change, or the person a paired agent acts for (RegentsWeb.Account.ProfileOwner).
  pipeline :profile_owner do
    plug RegentsWeb.Account.ProfileOwner
  end

  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :public_documents do
    plug :accepts, ["html"]
    plug :fetch_session
    # Read only, for the Agent Message form a page may hold (`AgentMessage`).
    plug :enforce_session_authority
    plug RegentsWeb.Plugs.Theme
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
    plug :put_product, "regents"
    plug :protect_from_forgery

    # Reading only: these pages never start sign-in, so they send no referrer.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.reading(),
      "referrer-policy" => "no-referrer"
    }
  end

  # The saved errors: the site's admins only. Anyone else gets the not-found page under
  # the reading policy; an admin's page replaces it with one carrying this
  # request's nonce (RegentsWeb.ErrorsAdmin).
  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :errors_admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.reading(),
      "referrer-policy" => "no-referrer"
    }

    plug RegentsWeb.ErrorsAdmin
  end

  # The team's own pages after the admin check above: the site's page frame.
  pipeline :admin_page do
    plug :fetch_live_flash
    plug RegentsWeb.Plugs.Theme
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
    plug :put_product, "regents"
  end

  # Techtree's pages: the page is Techtree's (its palette and stylesheets), read
  # inside Techtree's own frame (RegentsWeb.Techtree), also answering Markdown
  # via PageMarkdown when asked with `Accept: text/markdown`.
  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :techtree_browser do
    plug :accepts, ["html", "md"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug RegentsWeb.Plugs.RequireArticleAdmin
    plug RegentsWeb.Plugs.Theme
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
    plug :put_product, "techtree"
    plug RegentsWeb.Plugs.LaunchGate
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.sign_in()
    }

    plug RegentsWeb.Techtree.Plugs.PageMarkdown
  end

  pipeline :techtree do
    plug :put_product, "techtree"
    plug :put_layout, html: {RegentsWeb.Techtree.Layouts, :app}
  end

  # Binary downloads on Techtree's browser session (project archive): no HTML/MD
  # content negotiation and no PageMarkdown interception, so `Accept: application/gzip`
  # and `*/*` work cleanly while preserving session authority and secure headers.
  # sobelow_skip ["Config.CSP"]
  pipeline :techtree_download do
    plug :fetch_session
    plug :enforce_session_authority
    plug RegentsWeb.Plugs.LaunchGate
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.reading()
    }
  end

  # Binary downloads on Techtree's agent API (project archive): no `:accepts, ["json"]`
  # so `Accept: application/gzip` or `application/octet-stream` succeed while JSON
  # error responses still format as JSON.
  pipeline :techtree_api_download do
    plug :put_format, "json"
    plug RegentsWeb.Plugs.LaunchGate
  end

  # The unified hosted MCP server: refused on the read-only venue, then admitted
  # by McpAgent (SIWA paired agent or Regents.OAuth Bearer token). No cookies or
  # sessions are read.
  pipeline :mcp do
    plug :put_format, "json"
    plug RegentsWeb.Plugs.LaunchGate
    plug RegentsWeb.Plugs.ReadOnly
    plug RegentsWeb.Plugs.McpAgent
  end

  # Keyfleet's pages: the page is Keyfleet's (its stylesheets), read inside
  # Keyfleet's own frame (RegentsWeb.Keyfleet).
  pipeline :keyfleet do
    plug :put_product, "keyfleet"
    plug :put_layout, html: {RegentsWeb.Keyfleet.Layouts, :app}
  end

  # The root layout draws the harbour's sea (`RegentsWeb.Keyfleet.HarbourSeaLive`)
  # behind Keyfleet's shell pages.
  pipeline :keyfleet_sea do
    plug :put_harbour_sea
  end

  # Keyfleet's open fleet directory in Markdown.
  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :keyfleet_directory do
    plug :put_format, "md"
    plug RegentsWeb.Plugs.LaunchGate

    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.reading()
    }
  end

  # Keyfleet's signed agent endpoints refuse requests against coming-soon fleets
  # and validate query strings and JSON body shapes before controllers run.
  pipeline :keyfleet_agent do
    plug RegentsWeb.Keyfleet.Plugs.AgentRequest
    plug RegentsWeb.Keyfleet.Plugs.FleetComingSoon
  end

  # A signed agent's live feed: no `:accepts`, since the answer is an event
  # stream, which a JSON-only door would refuse. Its refusals are JSON.
  pipeline :keyfleet_agent_feed do
    plug :put_format, "json"
    plug RegentsWeb.Plugs.LaunchGate
  end

  # Autolaunch's pages under /autolaunch/...: the page is Autolaunch's (its
  # stylesheets), read inside Autolaunch's own frame (RegentsWeb.Autolaunch).
  pipeline :autolaunch_prelaunch do
    plug RegentsWeb.Autolaunch.Prelaunch
  end

  pipeline :autolaunch_agent_swaps do
    plug :admit_autolaunch_feature, Regents.Autolaunch.AgentSwap
  end

  pipeline :autolaunch_agent_payments do
    plug :admit_autolaunch_feature, Regents.Autolaunch.AgentPayment
  end

  defp admit_autolaunch_feature(conn, feature) do
    if feature.enabled?() do
      conn
    else
      raise Phoenix.Router.NoRouteError, conn: conn, router: __MODULE__
    end
  end

  # ContentSecurityPolicy builds this policy, as it does for the browser pipeline.
  # sobelow_skip ["Config.CSP"]
  pipeline :autolaunch do
    plug RegentsWeb.Autolaunch.Prelaunch

    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.autolaunch()
    }

    plug :put_product, "autolaunch"
    plug :put_layout, html: {RegentsWeb.Autolaunch.Layouts, :app}
  end

  # Patchbay's pages under /patchbay/...: the page is Patchbay's (its
  # stylesheets), read inside Patchbay's own frame (RegentsWeb.Patchbay).
  pipeline :patchbay do
    plug :put_product, "patchbay"
    plug :put_site_edition, :main
    plug :put_layout, html: {RegentsWeb.Patchbay.Layouts, :app}
  end

  # Marketing pages: mark the root document with `data-marketing`, `data-page`,
  # and the page's product identity so the marketing bar, framed layout, and
  # product palettes apply strictly on `/`, `/techtree`, `/keyfleet`,
  # `/autolaunch`, and `/patchbay`.
  pipeline :marketing_home do
    plug :put_product, "regents"
    plug :put_marketing_page, "home"
  end

  pipeline :marketing_techtree do
    plug :put_product, "techtree"
    plug :put_marketing_page, "product"
  end

  pipeline :marketing_keyfleet do
    plug :put_product, "keyfleet"
    plug :put_marketing_page, "product"
  end

  pipeline :marketing_autolaunch do
    plug :put_product, "autolaunch"
    plug :put_marketing_page, "product"
  end

  pipeline :marketing_patchbay do
    plug :put_product, "patchbay"
    plug :put_marketing_page, "product"
  end

  pipeline :marketing_cloak do
    plug :put_product, "cloak"
    plug :put_marketing_page, "product"
  end

  def put_marketing_page(conn, page), do: assign(conn, :marketing_page, page)

  def enforce_session_authority(conn, _opts) do
    RegentsWeb.Account.PrivySessionController.enforce_authority(conn)
  end

  defp private_response(conn, _opts),
    do: put_resp_header(conn, "cache-control", "private, no-store")

  # The product a page belongs to, one of `Regent.Site.products/0`'s ids. The root
  # layout puts it on the page as `data-product`, with its brand (`data-brand`) and
  # the home colour (`data-home`). A shell page names its own (`RouteCatalog`).
  def put_product(conn, product), do: assign(conn, :site_product, product)

  def put_current_path(conn, _opts), do: assign(conn, :current_path, conn.request_path)

  def put_site_edition(conn, edition), do: assign(conn, :site_edition, edition)

  def put_harbour_sea(conn, _opts), do: assign(conn, :harbour_sea, true)

  if Application.compile_env(:regents, :local_showcase, false) do
    # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
    # sobelow_skip ["Config.CSP"]
    pipeline :local_showcase do
      plug RegentsWeb.Showcase.LocalOnly
      plug :accepts, ["html", "json"]
      plug :fetch_session
      plug :enforce_session_authority
      plug :fetch_live_flash
      plug RegentsWeb.Plugs.Theme
      plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
      plug :put_product, "regents"
      plug :protect_from_forgery

      # The showcase includes the sign-in window and frames its own preview.
      plug :put_secure_browser_headers, %{
        "content-security-policy" => ContentSecurityPolicy.showcase()
      }
    end

    scope "/showcase", RegentsWeb do
      pipe_through :local_showcase
      get "/catalog", Showcase.CatalogController, :show
      get "/style.css", Showcase.CatalogController, :style

      live_session :local_showcase,
        session: {RegentsWeb.Live.Session, :render_context, []},
        on_mount: [RegentsWeb.Showcase.LocalOnly, {RegentsWeb.Live.Session, :load_human}] do
        live "/", ShowcaseLive, :index
        live "/preview", ShowcaseLive, :preview
        live "/privy", PrivyShowcaseLive, :index
      end
    end

    # The motion lab, local like the rest of the showcase.
    scope "/", RegentsWeb do
      pipe_through :local_showcase

      live_session :motion_lab,
        session: {RegentsWeb.Live.Session, :render_context, []},
        on_mount: [RegentsWeb.Showcase.LocalOnly] do
        live "/animations", AnimationsLive, :index
      end
    end
  end

  scope "/", RegentsWeb do
    get "/healthz", HealthController, :show
    get "/developers", PublicPagesController, :developers
    get "/openapi.json", PublicPagesController, :openapi
    get "/sitemap.xml", PublicPagesController, :sitemap
    get "/robots.txt", PublicPagesController, :robots
    get "/capabilities.json", PublicPagesController, :capabilities
    get "/agents.md", PublicPagesController, :agents
    get "/skill.md", PublicPagesController, :skill
    get "/pricing.md", PublicPagesController, :pricing
    get "/docs.md", PublicPagesController, :docs_markdown
    get "/docs-search.json", PublicPagesController, :docs_search

    for %{key: key} <- RegentsWeb.Docs.Pages.all(), is_binary(key) do
      get "/docs/#{key}.md", PublicPagesController, :docs_markdown, assigns: %{docs_key: key}
    end

    get "/llms.txt", PublicPagesController, :llms
    get "/server.json", PublicPagesController, :server_registry
    get "/mcp/server-card", PublicPagesController, :mcp_server_card
    get "/.well-known/security.txt", PublicPagesController, :security
    get "/.well-known/api-catalog", PublicPagesController, :api_catalog
    get "/.well-known/ai-catalog.json", PublicPagesController, :ai_catalog
    get "/.well-known/mcp/server-card.json", PublicPagesController, :mcp_server_card
    get "/.well-known/agent-skills/index.json", PublicPagesController, :agent_skills_index
    get "/.well-known/agent-skills/regents/SKILL.md", PublicPagesController, :agent_skills_regents
    get "/.well-known/hub-jwks.json", Keyfleet.HubJwksController, :show
    get "/paper-pro-daily.md", PaperPageController, :show
    get "/paper-pro-daily/pictures/:id", PaperPictureController, :show
    get "/paper-pro-daily/share.png", PaperPictureController, :page_share
    get "/paper-pro-daily/:paper/share.png", PaperPictureController, :paper_share
    get "/articles/covers/:slug", BlogCoverController, :show
    get "/agents/:wallet/picture", Account.AgentPictureController, :show
    get "/agents/:agent/skill.md", PublicPagesController, :agent_skill
    get "/autolaunch/images/:id/:digest", Autolaunch.StoredImageController, :launch
    get "/autolaunch/images/:id/:digest/:size", Autolaunch.StoredImageController, :launch
    get "/autolaunch/stock-images/:id/:digest", Autolaunch.StoredImageController, :stock
    get "/autolaunch/stock-images/:id/:digest/:size", Autolaunch.StoredImageController, :stock
    get "/autolaunch/auctions/:symbol/:tail/share.png", Autolaunch.ShareCardController, :auction

    get "/autolaunch/auctions/:symbol/:tail/share.mp4",
        Autolaunch.ShareCardController,
        :auction_video

    get "/autolaunch/tokens/:symbol/:tail/share.png", Autolaunch.ShareCardController, :token

    get "/autolaunch/tokens/:symbol/:tail/share.mp4",
        Autolaunch.ShareCardController,
        :token_video

    get "/autolaunch/tokens/:symbol/:tail/wallets/:wallet/share.mp4",
        Autolaunch.ShareCardController,
        :wallet_video

    get "/autolaunch/auctions/:symbol/:tail/wallets/:wallet/share.mp4",
        Autolaunch.ShareCardController,
        :auction_wallet_video

    get "/autolaunch/stock/isolated-afters/terms/:hash", Autolaunch.ExposureController, :terms

    get "/autolaunch/stock/isolated-afters/:series/share.png",
        Autolaunch.ShareCardController,
        :exposure

    get "/autolaunch/stock/isolated-afters/:series/share.mp4",
        Autolaunch.ShareCardController,
        :exposure_video

    get "/autolaunch/stock/isolated-afters/:series/wallets/:wallet/share.mp4",
        Autolaunch.ShareCardController,
        :exposure_wallet_video

    get "/autolaunch/stock/covered-call/:symbol/share.png",
        Autolaunch.ShareCardController,
        :covered_calls

    get "/autolaunch/stock/covered-call/:symbol/share.mp4",
        Autolaunch.ShareCardController,
        :covered_calls_video

    get "/autolaunch/stock/covered-call/:symbol/wallets/:wallet/share.mp4",
        Autolaunch.ShareCardController,
        :covered_calls_wallet_video

    get "/autolaunch/auctions/:auction_id/share.png",
        Autolaunch.OldLinkController,
        :base_auction_image

    get "/autolaunch/robinhood/auctions/:auction/share.png",
        Autolaunch.OldLinkController,
        :robinhood_auction_image

    get "/autolaunch/auctions/:auction_id", Autolaunch.OldLinkController, :base_auction

    get "/autolaunch/robinhood/auctions/:auction",
        Autolaunch.OldLinkController,
        :robinhood_auction

    get "/autolaunch/tokens/:token_id", Autolaunch.OldLinkController, :base_token
    get "/autolaunch/robinhood/tokens/:token", Autolaunch.OldLinkController, :robinhood_token
    get "/keyfleet/share/:file", Keyfleet.ShareCardController, :show
    get "/keyfleet/share/projects/:fleet_id/:file", Keyfleet.ShareCardController, :project
  end

  scope "/", RegentsWeb do
    pipe_through :public_documents

    get "/changelog", PublicPagesController, :show
    get "/agents", PublicPagesController, :show
    get "/agents/:agent", PublicPagesController, :show
  end

  scope "/api/v1" do
    pipe_through :api
    get "/health", RegentsWeb.HealthController, :status
    get "/docs", RegentsWeb.PublicPagesController, :document, assigns: %{document: "/docs"}
    get "/products", RegentsWeb.ProductsController, :index
    get "/products/:slug", RegentsWeb.ProductsController, :show
    get "/site-tools", RegentsWeb.SiteToolsController, :index
    get "/regents/:slug", RegentsWeb.Account.PublicRegentController, :show
    get "/site-tools/:site", RegentsWeb.SiteToolsController, :show

    for product <- ~w(patchbay techtree autolaunch keyfleet) do
      get "/#{product}/capabilities", RegentsWeb.ProductCapabilitiesController, :show,
        private: %{product: product}
    end
  end

  # Reads for the person a Privy sign-in names.
  scope "/api/v1" do
    pipe_through [:api, :read_only]
    get "/claims", RegentsWeb.Account.OwnedClaimsController, :index
    get "/staking/position", RegentsWeb.Stake.StakingPositionController, :show
  end

  # The person's own shared profile (RegentIdentity.HTTP), for its owner.
  scope "/api/v1" do
    pipe_through [:api, :read_only, :profile_owner]
    forward "/profile", RegentIdentity.HTTP
  end

  scope "/api/v1/reading", RegentsWeb do
    pipe_through :api
    get "/papers", ReadingController, :papers
    get "/papers/:id", ReadingController, :paper
    get "/articles", ReadingController, :articles
    get "/articles/:slug", ReadingController, :article
    get "/literature", ReadingController, :literature
  end

  scope "/api/agent/v1", RegentsWeb do
    pipe_through [:api, :paired_agent]
    get "/account", Account.AgentReadsController, :account
    get "/account/overview", Account.AgentReadsController, :overview
    post "/claims", Account.OwnedClaimsController, :agent_index
    get "/staking/position", Stake.StakingPositionController, :agent_show
  end

  # A paired agent's private message for the site's team.
  scope "/api/v1", RegentsWeb do
    pipe_through [:api, :paired_agent]
    post "/messages/:topic", MessagesController, :leave
  end

  # A paired agent's read of its person's Points, at the same path on every site.
  scope "/api/v1/account", RegentsWeb do
    pipe_through [:api, :paired_agent]
    get "/points", Account.AgentReadsController, :points
  end

  # Model Climb proofs: a paired agent sends its person's signed proofs and reads
  # them back; each is private to that person.
  scope "/api/v1/techtree/model-climb", RegentsWeb.Techtree do
    pipe_through [:api, :paired_agent]
    post "/reports", ModelClimbReportController, :create
    get "/reports", ModelClimbReportController, :index
    get "/reports/:digest", ModelClimbReportController, :show
  end

  # A paired agent's reads of the projects Techtree's team delivered to its
  # person, and its Uplift Factory order requests; each is private to that person.
  scope "/api/v1/techtree/account", RegentsWeb.Techtree do
    pipe_through [:api, :paired_agent]
    get "/projects", AgentAccountController, :projects
    get "/projects/:id", AgentAccountController, :project
    get "/orders", AccountOrdersController, :index
    post "/orders", AccountOrdersController, :create
    get "/orders/:id", AccountOrdersController, :show
    post "/orders/:id/cancel", AccountOrdersController, :cancel
  end

  scope "/api/v1/techtree/account", RegentsWeb.Techtree do
    pipe_through [:techtree_api_download, :paired_agent]
    get "/projects/:id/package", AgentAccountController, :package
  end

  # Operator-authenticated Uplift Factory OrderBridge endpoints
  # (`Authorization: Bearer <token>`, constant-time check inside controller).
  scope "/api/v1/techtree/factory", RegentsWeb.Techtree do
    pipe_through :api
    get "/orders", FactoryOrdersController, :index
    post "/orders/:id/deliver", FactoryOrdersController, :deliver
  end

  scope "/api/v1/techtree/factory", RegentsWeb.Techtree do
    pipe_through :techtree_api_download
    post "/orders/:id/claim", FactoryOrdersController, :claim
  end

  # Techtree's catalog and public run log, read by anyone: the exact bytes the
  # catalog and its bootstrap release were generated as, each object by its
  # digest, one Climb's summary, the published Results with each one's submitted
  # bundle, and a published Skill (RegentsWeb.Techtree.ExactResponse).
  scope "/api/v1/techtree", RegentsWeb.Techtree do
    pipe_through :api
    get "/catalog", CatalogController, :index
    get "/bootstrap", BootstrapController, :show
    get "/objects/:digest", ObjectController, :show
    get "/climbs/:slug", ClimbController, :show
    get "/publications", PublicationController, :index
    get "/publications/:bundle_digest", PublicationController, :show
    get "/publications/:bundle_digest/bundle", PublicationController, :bundle
    get "/publication-keys/:key_id", PublicationKeyController, :show
    get "/skills/:root_digest", PublishedSkillController, :show
  end

  # Techtree's signed publication and withdrawal endpoint: paired agent only,
  # refused automatically on the read-only venue by :paired_agent.
  scope "/api/v1/techtree", RegentsWeb.Techtree do
    pipe_through [:api, :paired_agent]
    post "/publications", PublicationController, :create
  end

  scope "/api/agents/v1" do
    pipe_through [:api, :read_only]
    forward "/", RegentAgents.HTTP
  end

  # Connected-app OAuth sign-in (`Regents.OAuth`) and consent. Strictly refused
  # on the read-only venue; while the connector is off, protocol routes answer
  # 404 and consent is refused.
  scope "/", RegentsWeb do
    pipe_through [:api, :read_only]

    get "/.well-known/oauth-protected-resource", OAuthController, :resource_metadata
    get "/.well-known/oauth-protected-resource/mcp", OAuthController, :resource_metadata
    get "/.well-known/oauth-authorization-server", OAuthController, :server_metadata
    post "/oauth/register", OAuthController, :register, log: false
    post "/oauth/token", OAuthController, :token, log: false
    post "/oauth/revoke", OAuthController, :revoke, log: false
  end

  scope "/oauth", RegentsWeb do
    pipe_through [:read_only, :browser]

    get "/authorize", OAuthController, :authorize, log: false
    post "/authorize", OAuthController, :approve, log: false
    get "/connections", OAuthController, :connections, log: false
    post "/connections/revoke", OAuthController, :revoke_connection, log: false
  end

  # Unified hosted MCP server at `/mcp`, spanning Regents identity tools,
  # Keyfleet workspaces, Autolaunch markets and wallet reviews, Patchbay forums
  # and Agent Offers, and Techtree results and benchmarks.
  scope "/" do
    pipe_through :mcp

    forward "/mcp",
            AshAi.Mcp.Router,
            [
              otp_app: :regents,
              mcp_name: "regents",
              instructions: &__MODULE__.mcp_instructions/1,
              list_ttl_ms: 0,
              read_ttl_ms: 0,
              cache_scope: "private",
              allowed_origins: &is_binary/1,
              tool_argument_transformer: &__MODULE__.mcp_check_input/3
            ],
            log: false
  end

  @doc "Instructions returned on MCP initialize."
  def mcp_instructions(_opts), do: RegentsWeb.PublicDocuments.mcp_instructions()

  @doc false
  def mcp_check_input(tool, args, ctx) do
    if RegentsWeb.Keyfleet.ToolErrors.keyfleet_tool?(tool),
      do: RegentsWeb.Keyfleet.ToolErrors.check_input(tool, args, ctx),
      else: RegentsWeb.Autolaunch.ToolErrors.check_input(tool, args, ctx)
  end

  scope "/", RegentsWeb do
    pipe_through [:browser, :marketing_home]

    live_session :home, session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/", HomeLive, :home
    end
  end

  scope "/", RegentsWeb do
    pipe_through [:browser, :marketing_techtree]

    live_session :marketing_techtree, session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/techtree", MarketingProductLive, :techtree
    end
  end

  scope "/", RegentsWeb do
    pipe_through [:browser, :marketing_keyfleet]

    live_session :marketing_keyfleet, session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/keyfleet", MarketingProductLive, :keyfleet
    end
  end

  scope "/", RegentsWeb do
    pipe_through [:browser, :marketing_autolaunch]

    live_session :marketing_autolaunch, session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/autolaunch", MarketingProductLive, :autolaunch
    end
  end

  scope "/", RegentsWeb do
    pipe_through [:browser, :marketing_patchbay]

    live_session :marketing_patchbay, session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/patchbay", MarketingProductLive, :patchbay
    end
  end

  scope "/", RegentsWeb do
    pipe_through [:browser, :marketing_cloak]

    live_session :marketing_cloak, session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/cloak", MarketingProductLive, :cloak
      live "/cloak/download/mac", MarketingProductLive, :cloak_download
      live "/cloak/install", MarketingProductLive, :cloak_install
    end
  end

  scope "/", RegentsWeb do
    pipe_through :browser

    get "/privacy", LegalController, :privacy
    get "/terms", LegalController, :terms

    post "/visit-log", VisitLogController, :create, log: false

    live_session :product_shell,
      session: {RegentsWeb.Live.Session, :render_context, []},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        {RegentsWeb.Live.Session, :load_human},
        RegentsWeb.Live.ArticleAdminHook
      ] do
      live "/app", ShellLive, :app
      live "/articles", ShellLive, :blog
      live "/articles/:slug", ShellLive, :blog_post
      live "/start", ShellLive, :agent_start
      live "/paper-pro-daily", ShellLive, :paper_pro_daily
      live "/paper-pro-daily/:paper", ShellLive, :paper_pro_daily_paper
      live "/literature", ShellLive, :literature
      live "/about", ShellLive, :about
      live "/docs", ShellLive, :docs
      live "/docs/:page", ShellLive, :docs_page
      live "/docs/:product/:page", ShellLive, :docs_subpage
      live "/account", ShellLive, :account
      live "/account/agents", ShellLive, :account_agents
      live "/account/points", ShellLive, :points
      live "/account/wallets", ShellLive, :wallets
      live "/account/connections", ShellLive, :connections
      live "/account/names", ShellLive, :names
      live "/pair", ShellLive, :pair
      live "/regents/:slug", ShellLive, :regent_profile
      live "/stake", ShellLive, :stake
      live "/redeem", ShellLive, :redeem
      live "/redeem/gallery", ShellLive, :redeem_gallery
      live "/siwa", ShellLive, :siwa
      live "/admin/articles", ShellLive, :articles_admin
    end
  end

  # Sign-in's own addresses. The read-only refusal comes first, so it answers
  # before the forms token is checked.
  scope "/auth", RegentsWeb.Account do
    pipe_through [:read_only, :browser]

    get "/csrf", PrivySessionController, :csrf
    post "/privy/failure", PrivySessionController, :failure
    post "/privy/session", PrivySessionController, :create
    get "/session", PrivySessionController, :show
    delete "/privy/session", PrivySessionController, :delete
  end

  # Permanent redirects from retired legacy Techtree paths under `/techtree/*`.
  # Declared ahead of the LiveView scope so `/techtree/docs/method` resolves
  # before `/techtree/docs/:slug`.
  scope "/techtree", RegentsWeb.Techtree do
    get "/start", RedirectController, :start
    get "/verify", RedirectController, :verify
    get "/docs/method", RedirectController, :verify
    get "/repo2rlenv", RedirectController, :environments
    get "/train", RedirectController, :models
    get "/services/verify", RedirectController, :evals
    get "/services/verify/sample-report", RedirectController, :results
    get "/services/cyber-assist", RedirectController, :security
    get "/services/cyber-assist/sample-report", RedirectController, :security_sample_report
    get "/services/watchdog", RedirectController, :security
  end

  scope "/techtree", RegentsWeb.Techtree do
    pipe_through :techtree_download
    get "/account/projects/:id/package", ProjectPackageController, :show
  end

  scope "/techtree", RegentsWeb.Techtree do
    pipe_through [:techtree_browser, :techtree]

    get "/about", PublicPagesController, :show
    get "/privacy", PublicPagesController, :show
    get "/terms", PublicPagesController, :show
    get "/blog", BlogController, :index
    get "/blog/:slug", BlogController, :show
    get "/agents", PublicPagesController, :show
    get "/agents/:agent", PublicPagesController, :show
    get "/services/security/sample-report", PublicPagesController, :show

    live_session :techtree,
      session: {RegentsWeb.Live.Session, :render_context, []},
      layout: {RegentsWeb.Techtree.Layouts, :app},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        {RegentsWeb.Live.Session, :load_human},
        {RegentsWeb.Techtree.Layouts, :page}
      ] do
      live "/app", HomeLive
      live "/changelog", ChangelogLive
      live "/services/skills", ServiceLive, :skills
      live "/services/evals", ServiceLive, :evals
      live "/services/environments", ServiceLive, :environments
      live "/services/models", ServiceLive, :models
      live "/services/security", ServiceLive, :security
      live "/services/swarm-verify", ServiceLive, :swarm_verify
      live "/formal", FormalLive
      live "/train/:slug", TrainLive.Show
      live "/results", RunsLive.Index
      live "/results/:bundle_digest", RunsLive.Show
      live "/examples/tdd", TddShowcaseLive
      live "/climbs/:slug", ClimbsLive.Show
      live "/docs", DocsLive
      live "/docs/:slug", DocsLive
      live "/wallet-bench", WalletBenchLive.Index
      live "/wallet-bench/:id", WalletBenchLive.Show
      live "/account/projects", ProjectsLive, :index
      live "/account/projects/:id", ProjectsLive, :show
      live "/watchdog", WatchdogLive, :index
    end
  end

  # Compatibility for legacy edge redirects still mounted on the former hosts.
  scope "/", RegentsWeb do
    for product <- ~w(autolaunch keyfleet patchbay techtree) do
      get "/#{product}/mcp", CutoverRedirectController, :mcp_read
      post "/#{product}/mcp", CutoverRedirectController, :mcp_write
      get "/#{product}/robots.txt", CutoverRedirectController, :robots
      get "/#{product}/sitemap.xml", CutoverRedirectController, :sitemap
    end
  end

  # Techtree's agent guide, the Techtree skill and each agent's own skill, Markdown
  # to any caller, as the site's own /agents.md is, each Skill comparison's report,
  # the exact committed bytes, a published Result's share picture, for whoever asks,
  # a site making a link preview included, and the Wallet Bench as Markdown.
  scope "/techtree", RegentsWeb do
    get "/llms.txt", ProductAgentDocsController, :llms, private: %{product: "techtree"}

    get "/capabilities.json", ProductCapabilitiesController, :show,
      private: %{product: "techtree"}
  end

  scope "/techtree", RegentsWeb.Techtree do
    get "/agents.md", AgentsController, :show
    get "/skill.md", PublicPagesController, :skill_guide
    get "/agents/:agent/skill.md", PublicPagesController, :agent_skill_guide
    match :*, "/oauth/*rest", PublicPagesController, :redirect_oauth
    get "/train/:slug/report.json", TrainController, :report
    get "/results/:bundle_digest/share.png", ResultShareCardController, :show
    get "/wallet-bench.md", WalletBenchController, :markdown
    get "/wallet-bench/:id/evidence/:turn/:file", WalletBenchEvidenceController, :show
    get "/wallet-bench/:id/results.zip", WalletBenchEvidenceController, :results
  end

  # Every Skill comparison, the Wallet Bench scores and one wallet test's record,
  # for agents and other sites.
  scope "/techtree", RegentsWeb.Techtree do
    pipe_through :api
    get "/train.json", TrainController, :index
    get "/wallet-bench.json", WalletBenchController, :scores
    get "/wallet-bench/:id/results.json", WalletBenchEvidenceController, :summary
  end

  scope "/keyfleet", RegentsWeb.Keyfleet do
    pipe_through [:browser, :keyfleet]

    live_session :keyfleet_home,
      session: {RegentsWeb.Live.Session, :render_context, []},
      layout: {RegentsWeb.Keyfleet.Layouts, :app},
      on_mount: [RegentsWeb.Live.LaunchGateHook, {RegentsWeb.Live.Session, :load_human}] do
      live "/app", HomeLive, :home
    end

    # A Key holder's way into the fleet's notebooks, or to one saved output.
    get "/fleets/:fleet_id/notebooks/open", NotebookOpenController, :open
  end

  scope "/keyfleet", RegentsWeb.Keyfleet do
    pipe_through [:browser, :keyfleet, :keyfleet_sea]

    live_session :keyfleet,
      session: {RegentsWeb.Keyfleet.ShellLive, :render_context, []},
      layout: {RegentsWeb.Keyfleet.Layouts, :app},
      on_mount: [RegentsWeb.Live.LaunchGateHook, {RegentsWeb.Live.Session, :load_human}] do
      live "/about", ShellLive, :about
      live "/opportunities", ShellLive, :opportunities
      live "/docs", ShellLive, :docs
      live "/changelog", ShellLive, :changelog
      live "/agents", ShellLive, :agents
      live "/agents/:agent", ShellLive, :agent
      live "/privacy", ShellLive, :privacy
      live "/terms", ShellLive, :terms

      # Every fleet's pages, at the fleet's own address (RouteCatalog).
      for %{fleet_id: fleet_id, live_action: action, path_pattern: "/keyfleet" <> path}
          when fleet_id != nil <- RegentsWeb.Keyfleet.RouteCatalog.entries() do
        live path, ShellLive, action
      end
    end
  end

  scope "/keyfleet", RegentsWeb.Keyfleet do
    pipe_through :keyfleet_directory

    get "/fleets.md", DirectoryController, :index_md
    get "/fleets/:file", DirectoryController, :show_md
  end

  scope "/api/v1/keyfleet", RegentsWeb.Keyfleet do
    pipe_through :api

    get "/fleets", DirectoryController, :index_json
    get "/fleets/:fleet_id", DirectoryController, :show_json
    get "/fleets/:fleet_id/workspace/pulse", WorkspacePulseController, :show
    get "/fleets/:fleet_id/treasury", TreasuryController, :show
    get "/fleets/:fleet_id/proposals", PublicProposalsController, :index
    get "/fleets/:fleet_id/seasons", PublicSeasonsController, :index
    get "/fleets/:fleet_id/seasons/:number", PublicSeasonsController, :show
  end

  scope "/api/v1/keyfleet", RegentsWeb.Keyfleet do
    pipe_through [:api, :read_only]

    put "/avatar/upload/:ticket", AgentAvatarController, :upload
  end

  scope "/api/v1/keyfleet", RegentsWeb.Keyfleet do
    pipe_through [:keyfleet_agent_feed, :paired_agent]
    get "/feed", FeedController, :show
  end

  scope "/api/v1/keyfleet", RegentsWeb.Keyfleet do
    pipe_through [:api, :paired_agent, :keyfleet_agent]
    post "/feed/missed", FeedController, :missed
  end

  scope "/api/v1/keyfleet/agent", RegentsWeb.Keyfleet do
    pipe_through [:api, :paired_agent, :keyfleet_agent]

    post "/join/status", AgentProfileController, :status
    post "/profile/update", AgentProfileController, :update
    get "/profile", AgentProfileController, :show
    post "/avatar/start", AgentAvatarController, :start
    post "/avatar/remove", AgentAvatarController, :remove
    get "/shards", AgentShardController, :index
    post "/links/resolve", AgentLinkController, :resolve
    post "/keys/:fleet_id/:token_id/messages/read", AgentRoomController, :read_key_thread
    post "/keys/:fleet_id/:token_id/messages/send", AgentRoomController, :send_to_key
    post "/keys/:fleet_id/:token_id/messages/remove", AgentKeyController, :remove_from_wall
    post "/keys/:fleet_id/:token_id/messages/get", AgentRoomController, :get_key_message
    post "/fleets/:fleet_id/keys/held", AgentKeyController, :held
    get "/fleets/:fleet_id/keys/:token_id", AgentKeyController, :show
    post "/fleets/:fleet_id/posting_key", AgentKeyController, :choose_posting_key
    get "/fleets/:fleet_id/agent_keys", AgentKeyController, :agent_keys
    post "/fleets/:fleet_id/receipts", AgentReceiptController, :show
    get "/fleets/:fleet_id/doctor", AgentDoctorController, :show
    get "/fleets/:fleet_id/checkpoint", AgentCheckpointController, :show
    post "/fleets/:fleet_id/checkpoint/save", AgentCheckpointController, :save
    post "/fleets/:fleet_id/activity", AgentActivityController, :index
    post "/fleets/:fleet_id/search", AgentActivityController, :search
    get "/fleets/:fleet_id/rooms", AgentRoomController, :rooms
    post "/fleets/:fleet_id/rooms/create", AgentRoomController, :create_room
    post "/fleets/:fleet_id/rooms/:slug/topic", AgentRoomController, :set_topic
    post "/fleets/:fleet_id/rooms/:slug/messages/read", AgentRoomController, :read_messages
    post "/fleets/:fleet_id/rooms/:slug/messages/get", AgentRoomController, :get_message
    post "/fleets/:fleet_id/rooms/:slug/messages/send", AgentRoomController, :send_message
    post "/fleets/:fleet_id/sync", AgentRoomController, :sync
    get "/fleets/:fleet_id/polls", AgentPollController, :index
    post "/fleets/:fleet_id/polls/start", AgentPollController, :start
    get "/fleets/:fleet_id/polls/:poll_id", AgentPollController, :show
    post "/fleets/:fleet_id/polls/:poll_id/vote", AgentPollController, :vote
    post "/fleets/:fleet_id/polls/:poll_id/end", AgentPollController, :end_poll
    get "/fleets/:fleet_id/seasons", AgentSeasonController, :show
    post "/fleets/:fleet_id/seasons/pick", AgentSeasonController, :pick
    post "/fleets/:fleet_id/seasons/list", AgentSeasonController, :list
    post "/fleets/:fleet_id/seasons/:number/picks", AgentSeasonController, :picks
    get "/seasons/coins", AgentSeasonController, :coins
    get "/fleets/:fleet_id/projects", AgentProjectController, :index
    post "/fleets/:fleet_id/projects/start", AgentProjectController, :start
    post "/fleets/:fleet_id/projects/archive", AgentProjectController, :archive
    post "/fleets/:fleet_id/projects/:project/take_over", AgentProjectController, :take_over
    post "/fleets/:fleet_id/projects/:project/delete", AgentProjectController, :delete
    post "/fleets/:fleet_id/projects/:project/describe", AgentProjectController, :describe
    post "/fleets/:fleet_id/projects/:project/show", AgentProjectController, :show

    post "/fleets/:fleet_id/projects/:project/publications/list",
         AgentPublicationController,
         :index

    post "/fleets/:fleet_id/projects/:project/publications/posts",
         AgentPublicationController,
         :posts

    post "/fleets/:fleet_id/projects/:project/publications/commit",
         AgentPublicationController,
         :commit

    post "/fleets/:fleet_id/publications/items", AgentPublicationController, :item
    post "/fleets/:fleet_id/publications/pages", AgentPublicationController, :page

    post "/fleets/:fleet_id/publications/:publication_id/withdraw",
         AgentPublicationController,
         :withdraw

    get "/fleets/:fleet_id/projects/:project/code/pushes", AgentCodeController, :pushes
    post "/fleets/:fleet_id/projects/:project/code/commits", AgentCodeController, :commits
    get "/fleets/:fleet_id/projects/:project/code/commits/:commit", AgentCodeController, :commit
    post "/fleets/:fleet_id/projects/:project/code/file", AgentCodeController, :file
    post "/fleets/:fleet_id/projects/:project/notebooks/list", AgentNotebookController, :list
    post "/fleets/:fleet_id/projects/:project/notebooks/create", AgentNotebookController, :create

    post "/fleets/:fleet_id/projects/:project/notebooks/:notebook_id/files/list",
         AgentNotebookController,
         :list_files

    post "/fleets/:fleet_id/projects/:project/notebooks/:notebook_id/files/read",
         AgentNotebookController,
         :read_file

    post "/fleets/:fleet_id/projects/:project/notebooks/:notebook_id/files/add",
         AgentNotebookController,
         :add_file

    post "/fleets/:fleet_id/projects/:project/notebooks/:notebook_id/files/write",
         AgentNotebookController,
         :write_file

    post "/fleets/:fleet_id/projects/:project/notebooks/:notebook_id/lock",
         AgentNotebookController,
         :lock

    get "/fleets/:fleet_id/projects/:project/notebooks/copies", AgentNotebookController, :copies

    post "/fleets/:fleet_id/projects/:project/notebooks/copies/:copy_id/restore",
         AgentNotebookController,
         :restore

    post "/fleets/:fleet_id/projects/:project/notebooks/:notebook_id/runs/start",
         AgentNotebookController,
         :start

    get "/fleets/:fleet_id/projects/:project/notebooks/:notebook_id/runs/:run_id",
        AgentNotebookController,
        :show

    get "/fleets/:fleet_id/projects/:project/notebooks/:notebook_id/page",
        AgentNotebookController,
        :page

    get "/fleets/:fleet_id/mutes", AgentMuteController, :index
    post "/fleets/:fleet_id/keys/:token_id/mute", AgentMuteController, :create
    post "/fleets/:fleet_id/keys/:token_id/unmute", AgentMuteController, :delete
    get "/fleets/:fleet_id/keys/:token_id/dms", AgentDmController, :inbox
    get "/fleets/:fleet_id/keys/:token_id/dms/blocks", AgentDmController, :blocked
    post "/fleets/:fleet_id/keys/:token_id/dms/:other_token_id/read", AgentDmController, :read

    post "/fleets/:fleet_id/keys/:token_id/dms/:other_token_id/send",
         AgentDmController,
         :send_message

    post "/fleets/:fleet_id/keys/:token_id/dms/:other_token_id/delete", AgentDmController, :delete

    post "/fleets/:fleet_id/keys/:token_id/dms/:other_token_id/auto_delete",
         AgentDmController,
         :auto_delete

    post "/fleets/:fleet_id/keys/:token_id/dms/:other_token_id/block", AgentDmController, :block

    post "/fleets/:fleet_id/keys/:token_id/dms/:other_token_id/unblock",
         AgentDmController,
         :unblock

    post "/fleets/:fleet_id/dms/changes", AgentDmController, :changes
    post "/fleets/:fleet_id/proposals/read", AgentProposalController, :read
    post "/fleets/:fleet_id/presence", AgentChainController, :presence
    post "/fleets/:fleet_id/proposals/create", AgentChainController, :propose
    post "/fleets/:fleet_id/proposals/vote", AgentChainController, :vote
    post "/fleets/:fleet_id/proposals/cancel", AgentChainController, :cancel
    post "/fleets/:fleet_id/proposals/carry_out", AgentChainController, :carry_out
    post "/fleets/:fleet_id/split", AgentChainController, :split
    post "/fleets/:fleet_id/treasury/send_share", AgentChainController, :send_share
    post "/fleets/:fleet_id/treasury/convert", AgentChainController, :convert

    post "/fleets/:fleet_id/treasury/advances/:advance_id/return",
         AgentChainController,
         :return_advance

    post "/fleets/:fleet_id/treasury/launch", AgentChainController, :launch_upkeep
    post "/fleets/:fleet_id/keys/:token_id/claim", AgentChainController, :claim
    post "/fleets/:fleet_id/keys/claim", AgentChainController, :claim_all
    post "/fleets/:fleet_id/keys/buy", AgentChainController, :buy
    post "/fleets/:fleet_id/shards/issue", AgentChainController, :issue_shard
    post "/fleets/:fleet_id/shards/voting", AgentChainController, :agent_voting
    post "/fleets/:fleet_id/keys/:token_id/shards/end", AgentChainController, :end_shard
    post "/fleets/:fleet_id/keys/:token_id/club_claim", AgentChainController, :club_claim
    post "/fleets/:fleet_id/keys/:token_id/reveal", AgentChainController, :reveal
    post "/fleets/:fleet_id/keys/:token_id/expire_reveal", AgentChainController, :expire_reveal
    post "/fleets/:fleet_id/graph/board", AgentGraphController, :board
    post "/fleets/:fleet_id/graph/view", AgentGraphController, :view
    post "/fleets/:fleet_id/graph/get", AgentGraphController, :get_object
    post "/fleets/:fleet_id/graph/changes", AgentGraphController, :changes
    post "/fleets/:fleet_id/graph/packet", AgentGraphController, :packet
    post "/fleets/:fleet_id/graph/create", AgentGraphController, :create
    post "/fleets/:fleet_id/graph/patch", AgentGraphController, :patch
    post "/fleets/:fleet_id/graph/link", AgentGraphController, :link
    post "/fleets/:fleet_id/graph/unlink", AgentGraphController, :unlink
    post "/fleets/:fleet_id/graph/archive", AgentGraphController, :archive
    post "/fleets/:fleet_id/graph/join", AgentGraphController, :join
    post "/fleets/:fleet_id/graph/leave", AgentGraphController, :leave
    post "/fleets/:fleet_id/graph/submit", AgentGraphController, :submit
    post "/fleets/:fleet_id/graph/review", AgentGraphController, :review
    post "/fleets/:fleet_id/graph/fork", AgentGraphController, :fork
    post "/fleets/:fleet_id/graph/pin", AgentGraphController, :pin
    post "/fleets/:fleet_id/graph/unpin", AgentGraphController, :unpin
    post "/fleets/:fleet_id/atlas/swarm", AgentGraphController, :atlas_swarm
    post "/fleets/:fleet_id/atlas/things", AgentGraphController, :atlas_things
  end

  scope "/api/v1/autolaunch", RegentsWeb.Autolaunch do
    pipe_through [:api, :autolaunch_prelaunch]

    get "/auctions", AuctionController, :index
    get "/auction-counts", AuctionController, :counts
    get "/auctions/:id", AuctionController, :show
    post "/auctions/:id/bid-quote", AuctionController, :bid_quote
    get "/tokens", TokenController, :index
    get "/tokens/:id", TokenController, :show
    get "/treasury-security/:address", TreasuryController, :show
    get "/after-hour-stocks", ExposureController, :index
    get "/after-hour-stocks/:series", ExposureController, :show
    get "/earn/products", EarnController, :products
    get "/covered-calls/:symbol", CoveredCallsController, :book
    post "/covered-calls/:symbol/quote", CoveredCallsController, :quote
  end

  scope "/api/v1/autolaunch", RegentsWeb.Autolaunch do
    pipe_through [:api, :read_only, :human_api]

    get "/me/positions", MyPositionsController, :show
    get "/me/covered-calls/:symbol", CoveredCallsController, :mine
    get "/me/after-hour-stocks/:series", ExposureController, :mine
    get "/me/earn", EarnController, :mine
  end

  scope "/api/agent/v1/autolaunch", RegentsWeb.Autolaunch do
    pipe_through [:api, :autolaunch_prelaunch, :paired_agent]

    get "/drafts/:kind", AgentAccountController, :draft
    patch "/drafts/:kind", AgentAccountController, :save_draft
    get "/positions", AgentAccountController, :positions
    get "/covered-calls/:symbol/positions", CoveredCallsAgentController, :positions
    post "/covered-calls/:symbol/steps", CoveredCallsAgentController, :prepare
    get "/after-hour-stocks/:series/holdings", ExposureAgentController, :holdings
    post "/after-hour-stocks/:series/steps", ExposureAgentController, :prepare
    post "/earn/quote", EarnAgentController, :quote
    get "/earn/positions", EarnAgentController, :positions
    post "/earn/steps", EarnAgentController, :prepare
    post "/bids/steps", AgentBidController, :prepare
    post "/bids/:bid/steps", AgentBidController, :settle
    post "/robinhood/bids/steps", AgentRobinhoodBidController, :prepare
    post "/robinhood/bids/:bid/steps", AgentRobinhoodBidController, :settle
    post "/launches/:draft/steps", AgentLaunchController, :prepare
    post "/auctions/:auction_id/finish/steps", AgentFinishController, :prepare
    post "/tokens/:token_id/stake/steps", AgentStakeController, :prepare
  end

  scope "/api/agent/v1/autolaunch", RegentsWeb.Autolaunch do
    pipe_through [:autolaunch_agent_swaps, :api, :autolaunch_prelaunch, :paired_agent]
    post "/tokens/:token_id/swap/steps", AgentSwapController, :prepare
  end

  scope "/api/agent/v1/autolaunch", RegentsWeb.Autolaunch do
    pipe_through [:autolaunch_agent_payments, :api, :autolaunch_prelaunch, :paired_agent]
    post "/tokens/:token_id/payment/steps", AgentPaymentController, :prepare
  end

  scope "/autolaunch", RegentsWeb do
    get "/llms.txt", ProductAgentDocsController, :llms, private: %{product: "autolaunch"}
    get "/agents.md", ProductAgentDocsController, :agents, private: %{product: "autolaunch"}
    get "/skill.md", ProductAgentDocsController, :skill, private: %{product: "autolaunch"}
  end

  scope "/autolaunch", RegentsWeb.Autolaunch do
    pipe_through [:browser, :autolaunch]

    get "/about", PublicPagesController, :show
    get "/changelog", PublicPagesController, :show
    get "/docs", PublicPagesController, :show
    get "/agents", PublicPagesController, :show
    get "/agents/:agent", PublicPagesController, :show
    get "/privacy", PublicPagesController, :show
    get "/terms", PublicPagesController, :show
    get "/blog", BlogController, :index
    get "/blog/:slug", BlogController, :show
    get "/unavailable", UnavailableController, :show

    # The home page's tab title has no " · Autolaunch" ending, so a page
    # reached from it is loaded fresh, as on autolaunch.sh: its own session.
    live_session :autolaunch_home,
      session: {RegentsWeb.Live.Session, :render_context, []},
      layout: {RegentsWeb.Autolaunch.Layouts, :app},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        RegentsWeb.Autolaunch.Prelaunch,
        {RegentsWeb.Live.Session, :load_human},
        {RegentsWeb.Autolaunch.Layouts, :page}
      ] do
      live "/app", HomeLive, :show
    end

    live_session :autolaunch,
      session: {RegentsWeb.Live.Session, :render_context, []},
      layout: {RegentsWeb.Autolaunch.Layouts, :app},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        RegentsWeb.Autolaunch.Prelaunch,
        {RegentsWeb.Live.Session, :load_human},
        {RegentsWeb.Autolaunch.Layouts, :page}
      ] do
      live "/create", StocksCreateLive, :create
      live "/agent-business", CreateLive, :create
      live "/how-it-works", HowItWorksLive, :show
      live "/auctions", AuctionsLive, :index
      live "/auctions/:symbol/:tail", MarketPageLive, :auction
      live "/tokens", TokensLive, :index
      live "/tokens/:symbol/:tail", MarketPageLive, :token
      live "/stocks", UpcomingLive, :show
      live "/upcoming", UpcomingLive, :show
      live "/stocks/:symbol", StockLive, :show
      live "/portfolio", PortfolioLive, :portfolio
      live "/portfolio/bids/:id", BidLive, :bid
      live "/regent", RegentLive, :regent
      live "/convert", ConvertLive, :index
      live "/stock/covered-call", CoveredCallsLive, :index
      live "/stock/isolated-afters", ExposureLive, :show
      live "/earn", EarnLive, :index
    end
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through [:patchbay_browser, :patchbay]

    get "/forum", Forum.BoardController, :home

    for board <- Regents.Patchbay.Forum.ProductBoards.all() do
      get "/#{board.slug}", Forum.BoardController, :product_board,
        private: %{product_board: board.slug}

      get "/#{board.slug}.md", Forum.BoardController, :product_board_md,
        private: %{product_board: board.slug}
    end

    get "/help", PagesController, :help
    get "/about", PagesController, :about
    get "/privacy", PagesController, :privacy
    get "/terms", PagesController, :terms
    get "/changelog", PagesController, :changelog
    get "/developers", PagesController, :developers
    get "/webmcp", PagesController, :webmcp
    get "/docs", PagesController, :docs
    get "/playbooks", PlaybookController, :index
    get "/playbooks/:slug", PlaybookController, :show
    get "/agents", PagesController, :agents
    get "/pair", PagesController, :pair
    get "/agents/:public_id", AgentProfileController, :show
    get "/errors/:code", ErrorLinkController, :show
    get "/discuss/techtree/:digest", TechtreeDiscussionController, :show
    get "/wallet-bench", WalletBenchController, :index
    get "/wallet-bench/how-it-works", WalletBenchController, :method
    get "/wallet-bench/:harness_id/:wallet_id", WalletBenchController, :show
    get "/incidents", IncidentController, :index
    get "/incidents.md", IncidentController, :index_md

    for incident <- Regents.Patchbay.Incidents.all() do
      get "/incidents/#{incident.name}", Forum.BoardController, :incident,
        private: %{incident: incident.name}

      get "/incidents/#{incident.name}.md", Forum.BoardController, :incident_md,
        private: %{incident: incident.name}
    end

    get "/moderation", Forum.ModerationController, :index
    get "/blog", BlogController, :index
    get "/blog/:slug", BlogController, :show
    get "/start", Forum.BoardController, :start
    get "/agent-setup", Forum.BoardController, :agent_setup
    get "/priority", Forum.BoardController, :priority
    get "/sites", Forum.BoardController, :sites
    get "/sites/:origin", Forum.BoardController, :old_site
    get "/sites/:origin/tools/:name", Forum.BoardController, :old_tool
    get "/posts/:id/:slug", Forum.BoardController, :post
    get "/posts/:id", Forum.BoardController, :post
    get "/reports/:id", Forum.BoardController, :post

    for agent <- ~w(claude dots grokbot hermes muse) do
      get "/#{agent}", Forum.BoardController, :home, private: %{home_page: agent}, log: false
    end

    for harness <- RegentsWeb.Patchbay.Forum.TroubleshootingPages.harnesses() do
      get "/#{RegentsWeb.Patchbay.Forum.TroubleshootingPages.slug(harness)}/troubleshooting",
          Forum.BoardController,
          :troubleshooting,
          private: %{harness: harness}
    end
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through [:read_only, :patchbay_browser, :patchbay]

    post "/threads/:id/replies", Forum.BoardController, :reply_thread
    post "/reports/:id/replies", Forum.BoardController, :create_reply
    post "/posts/:id/replies", Forum.BoardController, :create_reply
    post "/reports/:id/refund", Forum.BoardController, :refund
    post "/posts/:id/refund", Forum.BoardController, :refund
    post "/posts/:id/accept", Forum.BoardController, :accept
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through [:browser, :patchbay]

    live_session :patchbay_app,
      layout: {RegentsWeb.Patchbay.Layouts, :app},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        {RegentsWeb.Live.Session, :load_human},
        {RegentsWeb.Patchbay.CurrentProfile, :default},
        {RegentsWeb.Patchbay.Layouts, :page}
      ],
      session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/app", AppLive, :index
      live "/validate", ValidateLive, :index
    end

    live_session :patchbay_fixes,
      layout: {RegentsWeb.Patchbay.Layouts, :app},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        {RegentsWeb.Live.Session, :load_human},
        {RegentsWeb.Patchbay.CurrentProfile, :default},
        {RegentsWeb.Patchbay.Layouts, :page}
      ],
      session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/fixes/:id", FixLive.Show, :show
    end
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through [:browser, :patchbay]

    live_session :patchbay_offers,
      layout: {RegentsWeb.Patchbay.Layouts, :app},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        {RegentsWeb.Live.Session, :load_human},
        {RegentsWeb.Patchbay.CurrentProfile, :default},
        {RegentsWeb.Patchbay.Layouts, :page}
      ],
      session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/offers", OffersLive, :index
    end
  end

  scope "/patchbay/admin", RegentsWeb.Patchbay do
    pipe_through [:browser, :patchbay]

    live_session :patchbay_moderation,
      layout: {RegentsWeb.Patchbay.Layouts, :app},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        {RegentsWeb.Live.Session, :load_human},
        {RegentsWeb.Patchbay.CurrentProfile, :default},
        {RegentsWeb.Patchbay.Layouts, :page},
        RegentsWeb.Patchbay.Moderators
      ],
      session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/people", PeopleAdminLive, :index
      live "/people/:public_id", PersonAdminLive, :show
      live "/messages", AdminMessagesLive, :index
    end
  end

  scope "/patchbay/admin", RegentsWeb.Patchbay do
    pipe_through [:patchbay_offers, :browser, :patchbay]

    live_session :patchbay_offers_admin,
      layout: {RegentsWeb.Patchbay.Layouts, :app},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        RegentsWeb.Patchbay.OffersGate,
        {RegentsWeb.Live.Session, :load_human},
        {RegentsWeb.Patchbay.CurrentProfile, :default},
        {RegentsWeb.Patchbay.Layouts, :page},
        RegentsWeb.Patchbay.Moderators
      ],
      session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/offers", OffersAdminLive, :index
    end
  end

  scope "/patchbay/admin", RegentsWeb.Patchbay do
    pipe_through :errors_admin

    get "/ai-answers.csv", AnswerWatchController, :index
  end

  # Public feeds, Markdown guides, pictures, fix-check, known-fixes and diagnostic endpoints.
  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through :patchbay_public

    get "/solved.json", SolvedController, :feed
    get "/solved.rss", SolvedController, :rss
    get "/offers.md", OffersController, :markdown
    get "/skill.md", CommerceAPIController, :skill
    get "/llms.txt", CommerceAPIController, :llms
    get "/post-pictures/:id", PostPictureController, :show
    get "/site-screenshots/:site_id", SiteScreenshotController, :show
    get "/listed-site-pictures/:domain", ListedSitePictureController, :show

    for agent <- ~w(claude dots grokbot hermes muse) do
      get "/#{agent}/agents.md", Forum.BoardController, :agent_guide, private: %{home_page: agent}
    end

    for harness <- RegentsWeb.Patchbay.Forum.TroubleshootingPages.harnesses() do
      get "/#{RegentsWeb.Patchbay.Forum.TroubleshootingPages.slug(harness)}/troubleshooting.md",
          Forum.BoardController,
          :troubleshooting_md,
          private: %{harness: harness}
    end
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through :patchbay_html_or_json

    get "/known-fixes", KnownFixController, :index
    get "/known-fixes/:id", KnownFixController, :show
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through :api

    get "/fix-check", Forum.FixCheckController, :show
    get "/hello", ForumAPI.HelloController, :index
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through [:api, :patchbay_paired_agent]

    post "/known-fixes/:id", KnownFixController, :report
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through :patchbay_forum_tools

    post "/hello", ForumAPI.HelloController, :create
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through :patchbay_siwa_test

    get "/siwa-test", SiwaTestController, :show
  end

  scope "/patchbay/bench", RegentsWeb.Patchbay do
    pipe_through :patchbay_x402_test

    get "/x402-test", X402TestController, :show
  end

  scope "/patchbay/bench", RegentsWeb.Patchbay do
    pipe_through :api

    options "/x402-test", X402TestController, :preflight
    options "/mpp-test", MppTestController, :preflight
    get "/mpp-test", MppTestController, :show
  end

  # Patchbay public JSON APIs.
  scope "/api/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through :patchbay_api

    get "/services", CommerceAPIController, :services
    get "/endpoints", CommerceAPIController, :endpoints
    get "/playbooks", CommerceAPIController, :playbooks
    get "/playbooks/:slug", CommerceAPIController, :playbook
    post "/validate", CommerceAPIController, :validate
    get "/security/criticals", CommerceAPIController, :criticals
    post "/security/check-stack", CommerceAPIController, :check_stack
    get "/known-fixes", KnownFixController, :index
    get "/known-fixes/:id", KnownFixController, :show
    get "/sites", Forum.BoardController, :sites_json
    get "/sites/:host/tools/:name", Forum.BoardController, :tool_json
    get "/wallet-bench", WalletBenchController, :index
    get "/wallet-bench/:harness_id/:wallet_id", WalletBenchController, :show
    get "/offers", OffersController, :index
    get "/offers/campaigns/:campaign_id", OffersController, :manifest
    get "/forum/threads/:id", ForumAPI.ReportController, :show
    get "/forum/search", ForumAPI.ReportController, :search, log: false
    get "/forum/tool-history", ForumAPI.ToolController, :index
    get "/forum/capabilities", ForumAPI.ReportController, :capabilities
    get "/forum/help", ForumAPI.ReportController, :help
    get "/agents/:public_id", AgentAPI.ProfileController, :show
  end

  # Patchbay signed-in browser session JSON APIs.
  scope "/api/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through :patchbay_forum_tools

    get "/forum/readiness", ForumAPI.ReportController, :readiness
  end

  scope "/api/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through [:patchbay_forum_tools, :patchbay_require_profile]

    post "/forum/reports/:id/accept", ForumAPI.SolutionController, :create
    post "/forum/reports/:id/refund", ForumAPI.RefundController, :create
    get "/assists/:id", AssistAPI.RunController, :show
  end

  scope "/api/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through [
      :patchbay_forum_tools,
      :patchbay_payments,
      :patchbay_require_profile,
      :patchbay_payment_budget
    ]

    post "/payment_intents", PaymentsAPI.PaymentIntentController, :create
  end

  scope "/api/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through [:patchbay_forum_tools, :patchbay_payments, :patchbay_require_profile]

    post "/payment_intents/:id/execute", PaymentsAPI.PaymentIntentController, :pay
    get "/payment_intents/:id", PaymentsAPI.PaymentIntentController, :show
    get "/me/usdc_balance", PaymentsAPI.BalanceController, :show
  end

  # Patchbay signed agent APIs.
  scope "/api/agent/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through [:api, :patchbay_hello_proof]

    post "/hello", ForumAPI.HelloController, :create
  end

  scope "/api/agent/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through [:api, :patchbay_paired_agent]

    post "/messages/:topic", MessagesController, :leave
    post "/assists", AssistAPI.RunController, :create
    get "/assists/:id", AssistAPI.RunController, :show
    post "/forum/reports", ForumAPI.ReportController, :create
    post "/forum/reports/:id/replies", ForumAPI.ReportController, :create_reply
    post "/forum/threads", ForumAPI.ReportController, :create_thread
    post "/forum/threads/:id/replies", ForumAPI.ReportController, :create_thread_reply
    get "/forum/requests/:client_request_id", ForumAPI.ReportController, :request_status
    post "/forum/threads/:id/solution", ForumAPI.ReportController, :mark_solution
    post "/forum/replies/:id/uses", ForumAPI.ReportController, :record_use
    post "/forum/subscriptions", ForumAPI.ReportController, :subscribe
    delete "/forum/subscriptions/:id", ForumAPI.ReportController, :unsubscribe
    get "/forum/subscriptions", ForumAPI.ReportController, :subscriptions
    post "/forum/updates", ForumAPI.ReportController, :updates
    post "/forum/threads/:id/likes", ForumAPI.LikeController, :create
    delete "/forum/threads/:id/likes", ForumAPI.LikeController, :delete
    post "/forum/inbox", ForumAPI.InboxController, :index
    post "/forum/inbox/:id/acknowledge", ForumAPI.InboxController, :acknowledge
    post "/forum/sites/:site/refresh", ForumAPI.SiteRefreshController, :create
    post "/forum/agent-name", IdentityAPI.NameController, :agent
  end

  scope "/api/agent/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through [:api, :patchbay_paired_agent, :patchbay_payment_budget]

    post "/payment_intents", PaymentsAPI.PaymentIntentController, :create
    get "/payment_intents/:id", PaymentsAPI.PaymentIntentController, :show
  end

  scope "/api/agent/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through [:api, :patchbay_wallet_author, :patchbay_agent_payment_admission]

    post "/payment_intents/:id/execute", PaymentsAPI.PaymentIntentController, :execute
  end

  scope "/api/agent/v1/patchbay", RegentsWeb.Patchbay do
    pipe_through [:api, :patchbay_wallet_author]

    post "/payment_intents/:id/complete", PaymentsAPI.PaymentIntentController, :complete
  end

  # Canonical product agent entry point for Patchbay (before the `/:host` site catch-all).
  # `/patchbay/skill.md` and `/patchbay/llms.txt` are served by `CommerceAPIController` above.
  scope "/patchbay", RegentsWeb do
    get "/agents.md", ProductAgentDocsController, :agents, private: %{product: "patchbay"}
  end

  # A site's own page is its domain, as on patchbay.help. These stay the last
  # /patchbay routes, so no page of Patchbay's is ever read as a site.
  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through [:patchbay_browser, :patchbay]

    get "/:host", Forum.BoardController, :site
    get "/:host/tools/:name", Forum.BoardController, :tool
  end

  # Keyfleet's agent guides, contracts, metadata, hub JWKS, legacy redirects and fleet rooms redirect.
  scope "/keyfleet", RegentsWeb.Keyfleet do
    get "/skill.md", AgentFilesController, :skill
    get "/skill/:part", AgentFilesController, :part
    get "/agents/:agent/skill.md", AgentFilesController, :agent_skill
    get "/agent/git-remote-siwa", AgentFilesController, :git_helper
    get "/commands.json", AgentFilesController, :commands
    get "/llms.txt", PublicPagesController, :llms
    get "/agents.md", PublicPagesController, :agents
    get "/help", PublicPagesController, :help
    get "/capabilities.json", PublicPagesController, :capabilities
    get "/openapi.json", PublicPagesController, :openapi
    get "/api-contract.openapiv3.yaml", PublicPagesController, :api_contract
    match :*, "/oauth/*rest", PublicPagesController, :redirect_oauth
    get "/fleets/:fleet_id/rooms", DirectoryController, :rooms
    get "/metadata/collection.json", MetadataController, :collection
    get "/metadata/keys/:token_id", MetadataController, :show
    get "/.well-known/hub-jwks.json", HubJwksController, :show
  end

  scope "/admin" do
    pipe_through :errors_admin

    error_tracker_dashboard("/errors",
      on_mount: [RegentsWeb.ErrorsAdmin],
      csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    )
  end

  scope "/admin", RegentsWeb do
    pipe_through [:errors_admin, :admin_page]

    live_session :admin,
      session: {RegentsWeb.Live.Session, :render_context, []},
      on_mount: [RegentsWeb.ErrorsAdmin] do
      live "/messages", AdminMessagesLive, :index
      live "/pictures", AdminPicturesLive, :index
    end
  end
end
