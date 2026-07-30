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

  def enforce_privy_logout_epoch(conn, _opts) do
    AshPlatformWeb.PrivySessionController.enforce_logout_epoch(conn)
  end

  scope "/api", AshPlatformWeb do
    pipe_through :api

    get "/techtree/v1/tree/nodes", TechtreeNodeController, :index
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
      live "/autolaunch/create", ShellLive, :autolaunch_create
      live "/stake", ShellLive, :stake
      live "/redeem", ShellLive, :redeem
    end
  end
end
