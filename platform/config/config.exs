# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :regent_identity, repo: Regents.Repo, ash_domains: [RegentIdentity]
config :regent_payments, repo: Regents.Repo, ash_domains: [RegentPayments]

# Agents pair with a person's account through the agent pairing every Regent site
# shares (RegentAgents). `allowed` is what an agent may do here in each status,
# as GET /api/agents/v1/whoami tells it and priv/public/agents.md and the tools
# in priv/tool_manifest.json list it: true to the routes and policies, so change
# them together.
config :regent_agents,
  repo: Regents.Repo,
  pubsub: Regents.PubSub,
  notifications: Regents.Notifications,
  account: {Regents.AgentAccount, :account},
  allowed: %{
    "not_paired" => [
      "Read this site's public pages and docs, also with the regents_about, regents_products, regents_product, regents_research_list, regents_research_paper, regents_articles_list, regents_article, regents_literature and regents_public_profile tools.",
      "Check your status here at any time, also with the regents_agent_whoami tool.",
      "Pair with the code your person makes with Pair New Agent in the side panel."
    ],
    "person_not_here" => [
      "Read this site's public pages and docs, also with the regents_about, regents_products, regents_product, regents_research_list, regents_research_paper, regents_articles_list, regents_article, regents_literature and regents_public_profile tools.",
      "Check your status here at any time, also with the regents_agent_whoami tool.",
      "Reading for your person answers person_not_here until your person signs in on this site."
    ],
    "paired" => [
      "Read this site's public pages and docs, also with the regents_about, regents_products, regents_product, regents_research_list, regents_research_paper, regents_articles_list, regents_article, regents_literature and regents_public_profile tools.",
      "Check your status here at any time, also with the regents_agent_whoami tool, and check in for your person.",
      "Read your person's account, verified name claims and staking position, also with the regents_account, regents_claims and regents_stake_position tools.",
      "Read your person's Credits and Points, also with the regents_credits_balance, regents_credits_history, regents_credits_budget and regents_points_summary tools.",
      "You can never use your person's wallet, change their account or pair other agents.",
      # Changes together with RegentCredits.agent_grants_enabled?/0.
      "Spending your person's Credits isn't open to agents yet; your person can do it themselves."
    ]
  },
  ash_domains: [RegentAgents]

# Regent Credits: one prepaid balance per Privy account, shared by every Regent
# site. Credits are the private currency XRC, kept to the millionth. Admins come
# from REGENT_CREDITS_ADMINS at runtime. Purchases are checked through the
# site's own Base and Ethereum read endpoints; `rpc_url` is the public address a
# wallet adds each chain with. Balance changes from every site reach this
# site's PubSub.
config :ex_money,
  custom_currencies: [{:XRC, name: "Credits", digits: 6}],
  auto_start_exchange_rate_service: false

config :regent_credits,
  repo: Regents.Repo,
  pubsub: Regents.PubSub,
  notifications: Regents.Notifications,
  ash_domains: [RegentCredits],
  admins: [],
  chain_client: Regents.ChainClient,
  chains: %{
    base: %{chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"},
    ethereum: %{chain_id: 1, name: "Ethereum", rpc_url: "https://ethereum-rpc.publicnode.com"}
  }

# Regent Points: one private Points ledger per account, shared by every Regent
# site. Regents owns the `regent_points` schema's migrations and is the one site
# that tallies the NFT bonus at the end of each 30-day period. Earning starts only when Sean approves
# rules, a start time and each rule's source check.
config :regent_points,
  repo: Regents.Repo,
  pubsub: Regents.PubSub,
  accounts: Regents.Points.Accounts,
  chain_client: Regents.Points.ChainClient,
  ash_domains: [RegentPoints],
  program_id: "regents-points-v1",
  starts_at: nil,
  approved_rules: [],
  adapters: %{"credits.purchase_settled" => Regents.Points.CreditsPurchase}

# Ash 3.33 requires an explicit string length unit. Codepoints match how
# PostgreSQL counts `length()`, so `max_length` bounds stored size; graphemes
# (`:mixed`) do not, because one grapheme can carry unbounded combining marks
# (CVE-2026-82752).
config :ash, default_string_length_count: :codepoints

config :mime, :types, %{"application/yaml" => ["yaml"]}

config :regents,
  local_showcase: false,
  ash_domains: [
    Regents.Names,
    Regents.Accounts,
    Regents.Formation,
    Regents.OpenSea,
    Regents.Redemption,
    Regents.Staking,
    Regents.PaperProDaily,
    Regents.Points,
    Regents.Blog
  ],
  generators: [timestamp_type: :utc_datetime]

config :regents, ecto_repos: [Regents.Repo]

# The commit and Fly image a deployed machine runs; production sets both at boot.
config :regents, :build, %{commit: nil, release: nil}

# Background jobs live in the site's own schema, beside its tables. Queues hear
# about new jobs through Erlang process groups, across the site's machines.
# `regent_credits` checks Credits purchases on chain; AshOban adds each
# trigger's sweep to `cron`. `points` checks and awards Points; `points_chain`
# reads NFT holdings for the period-end bonus, tallied daily only on this site.
config :regents, Oban,
  repo: Regents.Repo,
  prefix: "regents_app",
  notifier: Oban.Notifiers.PG,
  queues: [default: 1, regent_credits: 3, points: 5, points_chain: 2, staking_reads: 1],
  cron: [
    crontab: [
      {"15 0 * * *", RegentPoints.TallyPeriods},
      {"@reboot", Regents.Staking.SnapshotRefresh},
      # Every five minutes, and early after a confirmed on-chain press or a press
      # of the read-again icon (Regents.ChainRefresh).
      {"*/5 * * * *", Regents.Staking.SnapshotRefresh},
      {"17 4 * * *", Regents.ErrorPruner}
    ]
  ],
  pruner: [max_age: {7, :days}],
  lifeline: [rescue_after: {10, :minutes}]

config :regents, :metrics_listener, ip: {127, 0, 0, 1}, port: 9091

config :regents, Regents.Repo,
  database: "regents_disabled",
  hostname: "127.0.0.1",
  port: 1,
  pool_size: 1

config :regents, :sprite_provider, RegentSprites
# Each paired agent's reading from the sign-in service, kept five minutes. Older
# readings leave with the generation the collector drops every ten minutes.
config :regents, Regents.Agents.ActivityReading,
  gc_interval: :timer.minutes(10),
  max_size: 10_000

config :regents, :session_bootstrap_rate_limit, limit: 30, window_seconds: 300
config :regents, :chain_read_rate_limit, limit: 30, window_seconds: 60
config :regents, :credits_report_rate_limit, limit: 120, window_seconds: 60

# Rate limits key on the direct peer. Production turns on Fly's client header.
config :regents, :behind_fly_proxy, false

config :regents, :base_read_rpc_url, "https://base-rpc.publicnode.com"
# ENS lives on Ethereum mainnet, which has no public endpoint this product is
# willing to trust: without one named at boot, no name or picture is looked up.
config :regents, :ethereum_read_rpc_url, nil
config :regents, :ethereum_rpc_module, AgentEns.Internal.RPC
config :regents, :ens_lookup_deadline_ms, 4_000
config :regents, :ens_avatar_http_client, Regents.Ens.AvatarHttpClient
config :regents, :ens_avatar_deadline_ms, 10_000
config :regents, :app_surfaces, true
config :regents, :opensea_api_key, nil
config :regents, :opensea_http_client, Regents.OpenSea.HttpClient
# Extra options for each read of a site's published tools (tests answer them here).
config :regents, Regents.SiteTools, req_options: []
config :regents, :opensea_live_lookups_per_minute, 60
config :regents, :opensea_lookups_per_minute, 6
config :regents, :opensea_holdings_clock, &Regents.OpenSea.HoldingsCache.monotonic_ms/0
# The clock request budgets count windows on; tests set it to hold or cross a window's edge.
config :regents, :rate_limiter_clock, &Regents.RateLimiter.monotonic_second/0
# Also bounds how often one address may be reset: once per window.
config :regents, :opensea_holdings_cache_ttl_ms, 15_000

# One shared Oban job warms and refreshes the durable staking projection every
# five minutes. Development disables this automatic work unless explicitly enabled.
config :regents, :staking_snapshot_refresh_enabled, true

# Who reads a chain again when a person's action may have changed it
# (`Regents.ChainRefresh`).
config :regents, Regents.ChainRefresh, readers: [Regents.Staking.SnapshotCache]

config :regents, :session_options,
  store: :cookie,
  key: "_regents_key",
  signing_salt: "OLoeAaio",
  same_site: "Lax",
  secure: false,
  http_only: true,
  # A sign-in lasts 30 days; Regents.Accounts.SessionAuthority refuses it after that too.
  max_age: 30 * 24 * 60 * 60

# Configure the endpoint
config :regents, RegentsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: RegentsWeb.ErrorHTML,
      json: RegentsWeb.ErrorJSON,
      md: RegentsWeb.ErrorMD
    ],
    layout: false
  ],
  pubsub_server: Regents.PubSub,
  live_view: [signing_salt: "RH19ZPg2"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  regents: [
    args:
      ~w(js/app.ts js/privy_bridge.tsx --bundle --splitting --format=esm --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --loader:.woff2=file --loader:.woff=file --loader:.ttf=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Mix.Project.deps_path(), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :visit, :actor, :surface, :event]

# Failed requests, pages and jobs are saved in the site's own schema and shown
# to Credits admins at /admin/errors. Only server faults, and only a job's last
# attempt, are saved (Regents.ErrorIgnorer), only where each one happened is kept
# (Regents.ErrorFilter), and Regents.ErrorPruner clears each one a week after it
# was last seen.
config :error_tracker,
  repo: Regents.Repo,
  otp_app: :regents,
  prefix: "regents_app",
  ignorer: Regents.ErrorIgnorer,
  filter: Regents.ErrorFilter

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
