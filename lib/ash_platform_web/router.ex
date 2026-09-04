defmodule AshPlatformWeb.Router do
  use AshPlatformWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug AshPlatformWeb.Plugs.Theme
    plug :put_root_layout, html: {AshPlatformWeb.Layouts, :root}
    plug AshPlatformWeb.Plugs.LaunchGate
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug AshPlatformWeb.Plugs.LaunchGate
  end

  pipeline :session_api do
    plug :accepts, ["json"]
    plug AshPlatformWeb.Plugs.LaunchGate
    plug :fetch_session
    plug :enforce_session_authority
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  def enforce_session_authority(conn, _opts) do
    AshPlatformWeb.PrivySessionController.enforce_authority(conn)
  end

  scope "/", AshPlatformWeb do
    get "/healthz", HealthController, :show
    get "/metrics", MetricsController, :show
  end

  scope "/api", AshPlatformWeb do
    pipe_through :api

    get "/autolaunch/v1/auctions", AutolaunchAuctionController, :index
    get "/autolaunch/v1/auctions/:id", AutolaunchAuctionController, :show
    post "/autolaunch/v1/auctions/:id/bid-quote", AutolaunchAuctionController, :bid_quote
    get "/autolaunch/v1/tokens", AutolaunchTokenController, :index
    get "/autolaunch/v1/treasury-security/:address", AutolaunchTreasuryController, :show

    post "/formation/v1/regents/:regent_id/agent-links/claim", AgentLinkController, :claim
  end

  scope "/api", AshPlatformWeb do
    pipe_through :session_api

    get "/formation/v1/regents/:regent_id/agent-links", AgentLinkController, :index
  end

  scope "/", AshPlatformWeb do
    pipe_through :browser

    live "/", HomeLive, :home
    get "/privacy", LegalController, :privacy
    get "/terms", LegalController, :terms

    get "/auth/csrf", PrivySessionController, :csrf
    post "/auth/privy/failure", PrivySessionController, :failure
    post "/auth/privy/session", PrivySessionController, :create
    get "/auth/session", PrivySessionController, :show
    delete "/auth/privy/session", PrivySessionController, :delete

    live_session :product_shell,
      session: {AshPlatformWeb.Live.Session, :render_context, []},
      on_mount: [AshPlatformWeb.Live.LaunchGateHook, {AshPlatformWeb.Live.Session, :load_human}] do
      live "/app", ShellLive, :app
      # Settings returns soon (founder, 2026-09-03): switched off, not removed.
      # live "/settings", ShellLive, :settings
      live "/formation", ShellLive, :formation
      live "/regents/:slug", ShellLive, :regent_profile
      live "/autolaunch", ShellLive, :autolaunch
      live "/autolaunch/auctions", ShellLive, :autolaunch_auctions
      live "/autolaunch/auctions/:auction_id", ShellLive, :autolaunch_auction
      live "/autolaunch/tokens", ShellLive, :autolaunch_tokens
      live "/autolaunch/tokens/:token_id", ShellLive, :autolaunch_token
      live "/autolaunch/launches", ShellLive, :autolaunch_launches
      live "/autolaunch/launches/:id", ShellLive, :autolaunch_launch
      live "/autolaunch/subjects", ShellLive, :autolaunch_subjects
      live "/autolaunch/subjects/:id", ShellLive, :autolaunch_subject
      live "/autolaunch/holdings", ShellLive, :autolaunch_holdings
      live "/autolaunch/create", ShellLive, :autolaunch_create
      live "/stake", ShellLive, :stake
      live "/redeem", ShellLive, :redeem
      live "/regents-club/metadata-cutover", ShellLive, :regents_club_metadata
    end
  end
end
