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
    plug :put_product, "regents"
    plug RegentsWeb.Plugs.LaunchGate
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

  # Where the site only reads, no agent is paired here, so a signed request is
  # refused plainly before the sign-in service is asked.
  pipeline :paired_agent do
    plug RegentsWeb.Plugs.ReadOnly
    plug RegentsWeb.Account.PairedAgent
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
  # inside Techtree's own frame (RegentsWeb.Techtree).
  pipeline :techtree do
    plug :put_product, "techtree"
    plug :put_layout, html: {RegentsWeb.Techtree.Layouts, :app}
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

    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.reading()
    }
  end

  # Keyfleet's signed agent endpoints refuse requests against coming-soon fleets.
  pipeline :keyfleet_agent do
    plug RegentsWeb.Keyfleet.Plugs.FleetComingSoon
  end

  # A signed agent's live feed: no `:accepts`, since the answer is an event
  # stream, which a JSON-only door would refuse. Its refusals are JSON.
  pipeline :keyfleet_agent_feed do
    plug :put_format, "json"
  end

  # Autolaunch's pages under /autolaunch/...: the page is Autolaunch's (its
  # stylesheets), read inside Autolaunch's own frame (RegentsWeb.Autolaunch).
  pipeline :autolaunch do
    plug :put_product, "autolaunch"
    plug :put_layout, html: {RegentsWeb.Autolaunch.Layouts, :app}
  end

  # Patchbay's pages under /patchbay/...: the page is Patchbay's (its
  # stylesheets), read inside Patchbay's own frame (RegentsWeb.Patchbay).
  pipeline :patchbay do
    plug :put_product, "patchbay"
    plug :put_layout, html: {RegentsWeb.Patchbay.Layouts, :app}
  end

  def enforce_session_authority(conn, _opts) do
    RegentsWeb.Account.PrivySessionController.enforce_authority(conn)
  end

  # The product a page belongs to, one of `Regent.Site.products/0`'s ids. The root
  # layout puts it on the page as `data-product`, with its brand (`data-brand`) and
  # the home colour (`data-home`). A shell page names its own (`RouteCatalog`).
  def put_product(conn, product), do: assign(conn, :site_product, product)

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
    get "/llms.txt", PublicPagesController, :llms
    get "/.well-known/security.txt", PublicPagesController, :security
    get "/.well-known/api-catalog", PublicPagesController, :api_catalog
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
  # person; each is private to that person.
  scope "/api/v1/techtree/account", RegentsWeb.Techtree do
    pipe_through [:api, :paired_agent]
    get "/projects", AgentAccountController, :projects
    get "/projects/:id", AgentAccountController, :project
    get "/projects/:id/package", AgentAccountController, :package
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

  scope "/", RegentsWeb do
    pipe_through :browser

    live_session :home, session: {RegentsWeb.Live.Session, :render_context, []} do
      live "/", HomeLive, :home
    end

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
      live "/cloak", ShellLive, :cloak
      live "/siwa", ShellLive, :siwa
      live "/cloak/install", ShellLive, :cloak_install
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

  scope "/techtree", RegentsWeb.Techtree do
    pipe_through [:browser, :techtree]

    get "/about", PublicPagesController, :show
    get "/agents", PublicPagesController, :show
    get "/agents/:agent", PublicPagesController, :show
    get "/services/security/sample-report", PublicPagesController, :show
    get "/account/projects/:id/package", ProjectPackageController, :show
    get "/wallet-bench/:id/evidence/:turn/:file", WalletBenchEvidenceController, :show
    get "/wallet-bench/:id/results.zip", WalletBenchEvidenceController, :results

    live_session :techtree,
      session: {RegentsWeb.Live.Session, :render_context, []},
      layout: {RegentsWeb.Techtree.Layouts, :app},
      on_mount: [{RegentsWeb.Live.Session, :load_human}, {RegentsWeb.Techtree.Layouts, :page}] do
      live "/", HomeLive
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

  # Techtree's agent guide, the Techtree skill and each agent's own skill, Markdown
  # to any caller, as the site's own /agents.md is, each Skill comparison's report,
  # the exact committed bytes, a published Result's share picture, for whoever asks,
  # a site making a link preview included, and the Wallet Bench as Markdown.
  scope "/techtree", RegentsWeb.Techtree do
    get "/agents.md", AgentsController, :show
    get "/skill.md", PublicPagesController, :skill_guide
    get "/agents/:agent/skill.md", PublicPagesController, :agent_skill_guide
    get "/train/:slug/report.json", TrainController, :report
    get "/results/:bundle_digest/share.png", ResultShareCardController, :show
    get "/wallet-bench.md", WalletBenchController, :markdown
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
      on_mount: [{RegentsWeb.Live.Session, :load_human}] do
      live "/", HomeLive, :home
    end

    # A Key holder's way into the fleet's notebooks, or to one saved output.
    get "/fleets/:fleet_id/notebooks/open", NotebookOpenController, :open
  end

  scope "/keyfleet", RegentsWeb.Keyfleet do
    pipe_through [:browser, :keyfleet, :keyfleet_sea]

    live_session :keyfleet,
      session: {RegentsWeb.Keyfleet.ShellLive, :render_context, []},
      layout: {RegentsWeb.Keyfleet.Layouts, :app},
      on_mount: [{RegentsWeb.Live.Session, :load_human}] do
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
    put "/avatar/upload/:ticket", AgentAvatarController, :upload
  end

  scope "/api/v1/keyfleet", RegentsWeb.Keyfleet do
    pipe_through [:keyfleet_agent_feed, :paired_agent]
    get "/feed", FeedController, :show
  end

  scope "/api/v1/keyfleet", RegentsWeb.Keyfleet do
    pipe_through [:api, :paired_agent]
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

  scope "/autolaunch", RegentsWeb.Autolaunch do
    pipe_through [:browser, :autolaunch]

    get "/about", PublicPagesController, :show
    get "/changelog", PublicPagesController, :show

    # The home page's tab title has no " · Autolaunch" ending, so a page
    # reached from it is loaded fresh, as on autolaunch.sh: its own session.
    live_session :autolaunch_home,
      session: {RegentsWeb.Live.Session, :render_context, []},
      layout: {RegentsWeb.Autolaunch.Layouts, :app},
      on_mount: [{RegentsWeb.Live.Session, :load_human}, {RegentsWeb.Autolaunch.Layouts, :page}] do
      live "/", HomeLive, :show
    end

    live_session :autolaunch,
      session: {RegentsWeb.Live.Session, :render_context, []},
      layout: {RegentsWeb.Autolaunch.Layouts, :app},
      on_mount: [{RegentsWeb.Live.Session, :load_human}, {RegentsWeb.Autolaunch.Layouts, :page}] do
      live "/how-it-works", HowItWorksLive, :show
      live "/auctions", AuctionsLive, :index
      live "/tokens", TokensLive, :index
      live "/tokens/:symbol/:tail", MarketPageLive, :token
    end
  end

  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through [:patchbay_browser, :patchbay]

    get "/", Forum.BoardController, :home
    get "/help", PagesController, :help
    get "/about", PagesController, :about
    get "/privacy", PagesController, :privacy
    get "/terms", PagesController, :terms
    get "/changelog", PagesController, :changelog
    get "/developers", PagesController, :developers
    get "/webmcp", PagesController, :webmcp
    get "/docs", PagesController, :docs
    get "/agents", PagesController, :agents
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

    for harness <- RegentsWeb.Patchbay.Forum.TroubleshootingPages.harnesses() do
      get "/#{RegentsWeb.Patchbay.Forum.TroubleshootingPages.slug(harness)}/troubleshooting",
          Forum.BoardController,
          :troubleshooting,
          private: %{harness: harness}
    end
  end

  # Each troubleshooting page's Markdown at its own address ending in .md, each
  # picture on a public post, and the pictures Patchbay took of sites, to any
  # caller, as on patchbay.help.
  scope "/patchbay", RegentsWeb.Patchbay do
    get "/post-pictures/:id", PostPictureController, :show
    get "/site-screenshots/:site_id", SiteScreenshotController, :show
    get "/listed-site-pictures/:domain", ListedSitePictureController, :show

    for harness <- RegentsWeb.Patchbay.Forum.TroubleshootingPages.harnesses() do
      get "/#{RegentsWeb.Patchbay.Forum.TroubleshootingPages.slug(harness)}/troubleshooting.md",
          Forum.BoardController,
          :troubleshooting_md,
          private: %{harness: harness}
    end
  end

  # A site's own page is its domain, as on patchbay.help. These stay the last
  # /patchbay routes, so no page of Patchbay's is ever read as a site.
  scope "/patchbay", RegentsWeb.Patchbay do
    pipe_through [:patchbay_browser, :patchbay]

    get "/:host", Forum.BoardController, :site
    get "/:host/tools/:name", Forum.BoardController, :tool
  end

  # Keyfleet's agent guides, metadata, hub JWKS and fleet rooms redirect, to any caller.
  scope "/keyfleet", RegentsWeb.Keyfleet do
    get "/skill.md", AgentFilesController, :skill
    get "/skill/:part", AgentFilesController, :part
    get "/agents/:agent/skill.md", AgentFilesController, :agent_skill
    get "/agent/git-remote-siwa", AgentFilesController, :git_helper
    get "/llms.txt", PublicPagesController, :llms
    get "/agents.md", PublicPagesController, :agents
    get "/help", PublicPagesController, :help
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
