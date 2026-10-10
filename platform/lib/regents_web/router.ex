defmodule RegentsWeb.Router do
  use RegentsWeb, :router

  alias RegentsWeb.ContentSecurityPolicy

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

  # Agents sign every request; each answer names the budget it was counted against.
  pipeline :agents do
    plug RegentsWeb.Plugs.AgentRateLimit
  end

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

  def enforce_session_authority(conn, _opts) do
    RegentsWeb.PrivySessionController.enforce_authority(conn)
  end

  if Application.compile_env(:regents, :local_showcase, false) do
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
  end

  scope "/", RegentsWeb do
    get "/healthz", HealthController, :show
    get "/developers", PublicPagesController, :developers
    get "/openapi.json", PublicPagesController, :openapi
    get "/sitemap.xml", PublicPagesController, :sitemap
    get "/robots.txt", PublicPagesController, :robots
    get "/llms.txt", PublicPagesController, :llms
    get "/.well-known/security.txt", PublicPagesController, :security
    get "/paper-pro-daily/pictures/:date", PaperPictureController, :show
    get "/articles/covers/:slug", BlogCoverController, :show
    get "/blog/covers/:slug", BlogController, :cover
  end

  scope "/", RegentsWeb do
    pipe_through :public_documents
    get "/docs", PublicPagesController, :show
    get "/about", PublicPagesController, :show
    get "/contact", PublicPagesController, :show
  end

  scope "/api/v1" do
    pipe_through :api
    get "/claims", RegentsWeb.OwnedClaimsController, :index
    get "/products", RegentsWeb.ProductsController, :index
    get "/products/:slug", RegentsWeb.ProductsController, :show
    get "/staking/position", RegentsWeb.StakingPositionController, :show
    forward "/profile", RegentIdentity.HTTP, otp_app: :regents
  end

  scope "/api/agents/v1" do
    pipe_through [:api, :agents]
    forward "/", RegentAgents.HTTP
  end

  scope "/", RegentsWeb do
    pipe_through :browser

    live "/", HomeLive, :home

    live_session :paper_reading,
      session: {RegentsWeb.Live.Session, :render_context, []},
      on_mount: [{RegentsWeb.Live.Session, :load_human}] do
      live "/paper-pro-daily", PaperProDailyLive, :paper_pro_daily
    end

    live_session :literature_reading,
      session: {RegentsWeb.Live.Session, :render_context, []},
      on_mount: [{RegentsWeb.Live.Session, :load_human}] do
      live "/literature", LiteratureLive, :literature
    end

    get "/privacy", LegalController, :privacy
    get "/terms", LegalController, :terms
    get "/blog", BlogController, :index
    get "/blog/:slug", BlogController, :show

    get "/auth/csrf", PrivySessionController, :csrf
    post "/auth/privy/failure", PrivySessionController, :failure
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
end
