# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :regent_identity, repo: Regents.Repo, ash_domains: [RegentIdentity]
config :regent_payments, repo: Regents.Repo, ash_domains: [RegentPayments]

config :regent_agents,
  repo: Regents.Repo,
  pubsub: Regents.PubSub,
  account: {Regents.AgentAccount, :account},
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
  ash_domains: [RegentCredits],
  admins: [],
  chain_client: Regents.ChainClient,
  on_credited: Regents.Credits.Credited,
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
    Regents.PaperProDaily
  ],
  generators: [timestamp_type: :utc_datetime]

config :regents, ecto_repos: [Regents.Repo]

# Background jobs live in the site's own schema, beside its tables. Queues hear
# about new jobs through Erlang process groups, across the site's machines.
# `regent_credits` checks Credits purchases on chain; AshOban adds each
# trigger's sweep to `cron`. `points` checks and awards Points; `points_chain`
# reads NFT holdings for the period-end bonus, tallied daily only on this site.
config :regents, Oban,
  repo: Regents.Repo,
  prefix: "regents_app",
  notifier: Oban.Notifiers.PG,
  queues: [regent_credits: 3, points: 5, points_chain: 2, staking_reads: 1],
  cron: [
    crontab: [
      {"15 0 * * *", RegentPoints.TallyPeriods},
      {"@reboot", Regents.Staking.SnapshotRefresh},
      {"* * * * *", Regents.Staking.SnapshotRefresh}
    ]
  ],
  pruner: [max_age: {7, :days}],
  lifeline: [rescue_after: {10, :minutes}]

config :regents, :metrics_listener, ip: {127, 0, 0, 1}, port: 9091

config :regents, Regents.Repo,
  database: "regents_disabled",
  hostname: "127.0.0.1",
  port: 1,
  pool_size: 1,
  migration_default_prefix: "regents_app"

config :regents, :sprite_provider, RegentSprites
config :regents, :siwa, base_url: nil, activity_read_token: nil
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
config :regents, :ens_avatar_deadline_ms, 2_000
config :regents, :app_surfaces, true
config :regents, :opensea_api_key, nil
config :regents, :opensea_http_client, Regents.OpenSea.HttpClient
config :regents, :opensea_live_lookups_per_minute, 60
config :regents, :opensea_lookups_per_minute, 6
config :regents, :opensea_holdings_clock, &Regents.OpenSea.HoldingsCache.monotonic_ms/0
# Also bounds how often one address may be reset: once per window.
config :regents, :opensea_holdings_cache_ttl_ms, 15_000

# One shared Oban job warms and refreshes the durable staking projection each
# minute. Development disables this automatic work unless explicitly enabled.
config :regents, :staking_snapshot_refresh_enabled, true

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
  metadata: [:request_id]

config :sentry,
  environment_name: config_env(),
  json_library: Jason,
  enable_metrics: false,
  tags: %{app: "regents"}

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
