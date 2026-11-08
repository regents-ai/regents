defmodule RegentsWeb.Router do
  use RegentsWeb, :router
  use ErrorTracker.Web, :router

  alias RegentsWeb.ContentSecurityPolicy

  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug RegentsWeb.Plugs.RequireArticleAdmin
    plug RegentsWeb.Plugs.Theme
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
    plug RegentsWeb.Plugs.LaunchGate
    plug :protect_from_forgery

    # These pages can start wallet sign-in.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.sign_in()
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug RegentsWeb.Plugs.LaunchGate
  end

  pipeline :paired_agent do
    plug RegentsWeb.Plugs.PairedAgent
  end

  # ContentSecurityPolicy builds this policy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :public_documents do
    plug :accepts, ["html"]
    plug :fetch_session
    plug RegentsWeb.Plugs.Theme
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
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

  def enforce_session_authority(conn, _opts) do
    RegentsWeb.PrivySessionController.enforce_authority(conn)
  end

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
    get "/llms.txt", PublicPagesController, :llms
    get "/.well-known/security.txt", PublicPagesController, :security
    get "/.well-known/api-catalog", PublicPagesController, :api_catalog
    get "/paper-pro-daily.md", PaperPageController, :show
    get "/paper-pro-daily/pictures/:id", PaperPictureController, :show
    get "/paper-pro-daily/share.png", PaperPictureController, :page_share
    get "/paper-pro-daily/:paper/share.png", PaperPictureController, :paper_share
    get "/articles/covers/:slug", BlogCoverController, :show
    get "/agents/:wallet/picture", AgentPictureController, :show
    get "/agents/:agent/skill.md", PublicPagesController, :agent_skill
  end

  scope "/", RegentsWeb do
    pipe_through :public_documents

    for path <- RegentsWeb.Docs.Pages.paths(),
        do: get(path, DocsController, :show, private: %{docs_path: path})

    get "/about", PublicPagesController, :show
    get "/changelog", PublicPagesController, :show
    get "/agents", PublicPagesController, :show
    get "/agents/:agent", PublicPagesController, :show
  end

  # The Claude connector's sign-in (Regents.OAuth). API credentials never use
  # cookies; consent uses the verified browser and CSRF pipeline. The resource's
  # metadata also answers under its /mcp path, where RFC 9728 places it.
  scope "/", RegentsWeb do
    pipe_through :api
    get "/.well-known/oauth-protected-resource", OAuthController, :resource_metadata
    get "/.well-known/oauth-protected-resource/mcp", OAuthController, :resource_metadata
    get "/.well-known/oauth-authorization-server", OAuthController, :server_metadata
    post "/oauth/register", OAuthController, :register, log: false
    post "/oauth/token", OAuthController, :token, log: false
    post "/oauth/revoke", OAuthController, :revoke, log: false
  end

  scope "/oauth", RegentsWeb do
    pipe_through :browser
    get "/authorize", OAuthController, :authorize, log: false
    post "/authorize", OAuthController, :approve, log: false
    get "/connections", OAuthController, :connections, log: false
    post "/connections/revoke", OAuthController, :revoke_connection, log: false
  end

  # The hosted MCP server: AshAi runs the tools the capabilities list as hosted
  # (`RegentsWeb.Capabilities.hosted_tools/0`), each as its Ash action with its
  # policies. McpAgent admits the request first: POST /mcp alone, JSON, one call,
  # no query string and no page from another site; then a paired agent signing
  # with its wallet or an app connected with a Bearer token from the sign-in
  # above, never neither. A connected app whose identity is paired calls as that
  # agent. So AshAi's own origin check takes whatever McpAgent let through.
  # A tool's input is checked as its action takes it, and refused with the code
  # HTTP gives (`RegentsWeb.ToolErrors.check_input/3`). No session, cookie or
  # CSRF token is read. Each account has its own budget here; the endpoint counts
  # each address first. Nothing is kept between requests. Tool calls carry pairing
  # codes, so nothing is logged. There is no `:accepts`: the endpoint already answers
  # /mcp in JSON, so a GET for an event stream hears McpAgent's 405, not a 406.
  pipeline :mcp do
    plug RegentsWeb.Plugs.LaunchGate
    plug RegentsWeb.Plugs.McpAgent
  end

  scope "/" do
    pipe_through :mcp

    forward "/mcp",
            AshAi.Mcp.Router,
            [
              otp_app: :regents,
              tools: RegentsWeb.Capabilities.hosted_tools(),
              mcp_name: "regents",
              instructions:
                "Regents, where people keep their Regents account and Points and pair the agents that work for them. " <>
                  "Every call is signed by a paired agent's own wallet, or carries the token of an app a person connected " <>
                  "to their account here. A paired agent reads its person's account with regents_account and their Points " <>
                  "with account_points; regents mcp signs each call for it. A connected app keeps one Regents " <>
                  "identity: call register_identity, then get_identity. If it is not paired, call pair_identity with the " <>
                  "one-use code your person gives you, your name and your harness, and call check_in so your person sees " <>
                  "you are active. Once paired, you work here as that agent: the account reads are yours as they are " <>
                  "any paired agent's. Never ask for a password, a private key or a wallet signature.",
              list_ttl_ms: 0,
              read_ttl_ms: 0,
              cache_scope: "private",
              allowed_origins: &is_binary/1,
              tool_argument_transformer: &RegentsWeb.ToolErrors.check_input/3
            ],
            log: false
  end

  scope "/api/v1" do
    pipe_through :api
    get "/health", RegentsWeb.HealthController, :status
    get "/docs", RegentsWeb.PublicPagesController, :document, assigns: %{document: "/docs"}
    get "/claims", RegentsWeb.OwnedClaimsController, :index
    get "/products", RegentsWeb.ProductsController, :index
    get "/products/:slug", RegentsWeb.ProductsController, :show
    get "/site-tools", RegentsWeb.SiteToolsController, :index
    get "/regents/:slug", RegentsWeb.PublicRegentController, :show
    get "/site-tools/:site", RegentsWeb.SiteToolsController, :show
    get "/staking/position", RegentsWeb.StakingPositionController, :show
    forward "/profile", RegentIdentity.HTTP, otp_app: :regents
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
    get "/account", AgentReadsController, :account
    post "/claims", OwnedClaimsController, :agent_index
    get "/staking/position", StakingPositionController, :agent_show
  end

  # A paired agent's read of its person's Points, at the same path on every site.
  scope "/api/v1/account", RegentsWeb do
    pipe_through [:api, :paired_agent]
    get "/points", AgentReadsController, :points
  end

  scope "/api/agents/v1" do
    pipe_through :api
    forward "/", RegentAgents.HTTP
  end

  scope "/", RegentsWeb do
    pipe_through :browser

    live_session :home, session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/", HomeLive, :home
    end

    get "/privacy", LegalController, :privacy
    get "/terms", LegalController, :terms

    get "/auth/csrf", PrivySessionController, :csrf
    post "/auth/privy/failure", PrivySessionController, :failure
    post "/visit-log", VisitLogController, :create, log: false
    post "/auth/privy/session", PrivySessionController, :create
    get "/auth/session", PrivySessionController, :show
    delete "/auth/privy/session", PrivySessionController, :delete

    live_session :product_shell,
      session: {RegentsWeb.Live.Session, :render_context, []},
      on_mount: [
        RegentsWeb.Live.LaunchGateHook,
        {RegentsWeb.Live.Session, :load_human},
        RegentsWeb.Live.AdminHook
      ] do
      live "/app", ShellLive, :app
      live "/articles", ShellLive, :blog
      live "/articles/:slug", ShellLive, :blog_post
      live "/start", ShellLive, :agent_start
      live "/paper-pro-daily", ShellLive, :paper_pro_daily
      live "/paper-pro-daily/:paper", ShellLive, :paper_pro_daily_paper
      live "/literature", ShellLive, :literature
      live "/account", ShellLive, :account
      live "/account/agents", ShellLive, :account_agents
      live "/account/points", ShellLive, :points
      live "/account/wallets", ShellLive, :wallets
      live "/account/connections", ShellLive, :connections
      live "/pair", ShellLive, :pair
      live "/names", ShellLive, :names
      live "/regents/:slug", ShellLive, :regent_profile
      live "/stake", ShellLive, :stake
      live "/redeem", ShellLive, :redeem
      live "/redeem/gallery", ShellLive, :redeem_gallery
      live "/autolaunch", ShellLive, :autolaunch
      live "/techtree", ShellLive, :techtree
      live "/patchbay", ShellLive, :patchbay
      live "/keyfleet", ShellLive, :keyfleet
      live "/cloak", ShellLive, :cloak
      live "/cloak/guide", ShellLive, :cloak_guide
      live "/admin/articles", ShellLive, :articles_admin
      live "/admin/pictures", ShellLive, :pictures_admin
    end
  end

  scope "/admin" do
    pipe_through :errors_admin

    error_tracker_dashboard("/errors",
      on_mount: [RegentsWeb.ErrorsAdmin],
      csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    )
  end
end
