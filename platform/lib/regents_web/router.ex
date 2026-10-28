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
    plug RegentsWeb.Plugs.Panels
    plug :put_root_layout, html: {RegentsWeb.Layouts, :root}
    plug RegentsWeb.Plugs.LaunchGate
    plug :protect_from_forgery

    # These pages can start wallet sign-in. Browser agents may use the tools the
    # pages register, from this site only.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.sign_in(),
      "permissions-policy" => "tools=(self)"
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
      "permissions-policy" => "tools=(self)",
      "referrer-policy" => "no-referrer"
    }
  end

  # The saved errors: Credits admins only. Anyone else gets the not-found page under
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
    get "/paper-pro-daily/pictures/:id", PaperPictureController, :show
    get "/articles/covers/:slug", BlogCoverController, :show
    get "/agents/:wallet/picture", AgentPictureController, :show
  end

  scope "/", RegentsWeb do
    pipe_through :public_documents
    get "/docs", PublicPagesController, :show
    get "/about", PublicPagesController, :show
    get "/contact", PublicPagesController, :show
  end

  scope "/api/v1" do
    pipe_through :api
    get "/health", RegentsWeb.HealthController, :status
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
    get "/credits/balance", AgentReadsController, :balance
    post "/credits/history", AgentReadsController, :history
    get "/credits/budget", AgentReadsController, :budget
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
        RegentsWeb.Live.ArticleAdminHook
      ] do
      live "/app", ShellLive, :app
      live "/articles", ShellLive, :blog
      live "/articles/:slug", ShellLive, :blog_post
      live "/start", ShellLive, :agent_start
      live "/paper-pro-daily", ShellLive, :paper_pro_daily
      live "/literature", ShellLive, :literature
      live "/account", ShellLive, :account
      live "/account/credits", ShellLive, :account_credits
      live "/account/points", ShellLive, :account_points
      live "/regents/:slug", ShellLive, :regent_profile
      live "/stake", ShellLive, :stake
      live "/redeem", ShellLive, :redeem
      live "/redeem/gallery", ShellLive, :redeem_gallery
      live "/autolaunch", ShellLive, :autolaunch
      live "/techtree", ShellLive, :techtree
      live "/patchbay", ShellLive, :patchbay
      live "/keyfleet", ShellLive, :keyfleet
      live "/credits/refunds", ShellLive, :credits_refunds
      live "/admin/credits", ShellLive, :credits_admin
      live "/admin/articles", ShellLive, :articles_admin
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
