defmodule AshPlatformWeb.Router do
  use AshPlatformWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AshPlatformWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", AshPlatformWeb do
    pipe_through :api

    get "/techtree/v1/tree/nodes", TechtreeNodeController, :index
  end

  scope "/", AshPlatformWeb do
    pipe_through :browser

    live "/", HomeLive, :home

    live_session :product_shell do
      live "/app", ShellLive, :app
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
      live "/autolaunch/create", ShellLive, :autolaunch_create
      live "/stake", ShellLive, :stake
      live "/redeem", ShellLive, :redeem
    end
  end
end
