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
    get "/skills/:root_digest", PublishedSkillController, :show
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
      live "/keyfleet", ShellLive, :keyfleet
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

      # Each fleet's pages, at the fleet's own address (RouteCatalog). Its
      # workspace, code, projects, worldline, atlas and messages are not open yet.
      for %{fleet_id: fleet_id, live_action: action, path_pattern: "/keyfleet" <> path}
          when fleet_id != nil and
                 action in [
                   :fleet,
                   :keys,
                   :seasons,
                   :proposals,
                   :proposal,
                   :treasury,
                   :polls,
                   :poll,
                   :search
                 ] <- RegentsWeb.Keyfleet.RouteCatalog.entries() do
        live path, ShellLive, action
      end
    end
  end

  scope "/autolaunch", RegentsWeb.Autolaunch do
    pipe_through [:browser, :autolaunch]

    get "/about", PublicPagesController, :show
    get "/changelog", PublicPagesController, :show

    live_session :autolaunch,
      session: {RegentsWeb.Live.Session, :render_context, []},
      layout: {RegentsWeb.Autolaunch.Layouts, :app},
      on_mount: [{RegentsWeb.Live.Session, :load_human}, {RegentsWeb.Autolaunch.Layouts, :page}] do
      live "/", HomeLive, :show
      live "/how-it-works", HowItWorksLive, :show
      live "/auctions", AuctionsLive, :index
      live "/tokens", TokensLive, :index
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
    get "/sites", Forum.BoardController, :sites
    get "/sites/:origin", Forum.BoardController, :site
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

  # Keyfleet's agent guides, to any caller, as the site's own are.
  scope "/keyfleet", RegentsWeb.Keyfleet do
    get "/skill.md", AgentFilesController, :skill
    get "/skill/:part", AgentFilesController, :part
    get "/agents/:agent/skill.md", AgentFilesController, :agent_skill
    get "/agent/git-remote-siwa", AgentFilesController, :git_helper
    get "/llms.txt", PublicPagesController, :llms
    get "/agents.md", PublicPagesController, :agents
    get "/help", PublicPagesController, :help
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
