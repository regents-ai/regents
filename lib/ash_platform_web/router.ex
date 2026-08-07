defmodule AshPlatformWeb.Router do
  use AshPlatformWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :enforce_privy_logout_epoch
    plug :fetch_live_flash
    plug :put_root_layout, html: {AshPlatformWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :agent_write_api do
    plug :accepts, ["json"]
    plug AshPlatform.AgentAuth.TechtreeWritePlug
  end

  pipeline :session_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :enforce_privy_logout_epoch
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  def enforce_privy_logout_epoch(conn, _opts) do
    AshPlatformWeb.PrivySessionController.enforce_logout_epoch(conn)
  end

  scope "/api", AshPlatformWeb do
    pipe_through :api

    get "/techtree/v1/trees", TechtreeReadController, :trees
    get "/techtree/v1/trees/:slug/nodes", TechtreeReadController, :tree_nodes
    get "/techtree/v1/nodes/:id", TechtreeReadController, :node
    get "/techtree/v1/nodes/:id/payload", TechtreeReadController, :payload
    get "/techtree/v1/tree/nodes", TechtreeNodeController, :index
    get "/autolaunch/v1/auctions", AutolaunchAuctionController, :index
    get "/autolaunch/v1/auctions/:id", AutolaunchAuctionController, :show
    post "/autolaunch/v1/auctions/:id/bid-quote", AutolaunchAuctionController, :bid_quote
    get "/autolaunch/v1/tokens", AutolaunchTokenController, :index

    post "/formation/v1/regents/:regent_id/agent-links/claim", AgentLinkController, :claim
  end

  scope "/api/techtree/v1", AshPlatformWeb do
    pipe_through :agent_write_api

    post "/nodes", TechtreePublicationController, :create
    post "/nodes/:id/evidence-state", TechtreeEvidenceController, :create
  end

  scope "/api", AshPlatformWeb do
    pipe_through :session_api

    post "/autolaunch/v1/auctions/:id/bids", AutolaunchAuctionController, :prepare_bid
    post "/autolaunch/v1/bids/:id/exit", AutolaunchAuctionController, :prepare_bid_exit
    post "/autolaunch/v1/bids/:id/return", AutolaunchAuctionController, :prepare_bid_return
    post "/autolaunch/v1/bids/:id/claim", AutolaunchAuctionController, :prepare_bid_claim

    get "/formation/v1/regents/:regent_id/agent-links", AgentLinkController, :index
  end

  scope "/", AshPlatformWeb do
    pipe_through :browser

    live "/", HomeLive, :home

    get "/auth/csrf", PrivySessionController, :csrf
    post "/auth/privy/session", PrivySessionController, :create
    get "/auth/session", PrivySessionController, :show
    delete "/auth/privy/session", PrivySessionController, :delete

    live_session :product_shell,
      on_mount: [{AshPlatformWeb.Live.Session, :load_human}] do
      live "/app", ShellLive, :app
      live "/settings", ShellLive, :settings
      live "/formation", ShellLive, :formation
      live "/regents/:slug", ShellLive, :regent_profile
      live "/techtree", ShellLive, :techtree
      live "/techtree/nodes/:node_id", ShellLive, :techtree_node
      live "/techtree/:tree_slug", ShellLive, :techtree_tree
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
    end
  end
end
