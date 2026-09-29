# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :regent_identity, repo: Regents.Repo, ash_domains: [RegentIdentity]
config :regent_payments, repo: Regents.Repo, ash_domains: [RegentPayments]

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
    Regents.Agents,
    Regents.Formation,
    Regents.OpenSea,
    Regents.Redemption,
    Regents.Staking
  ],
  generators: [timestamp_type: :utc_datetime]

config :regents, ecto_repos: [Regents.Repo]

config :regents, :metrics_listener, ip: {127, 0, 0, 1}, port: 9091

config :regents, Regents.Repo,
  database: "regents_disabled",
  hostname: "127.0.0.1",
  port: 1,
  pool_size: 1,
  migration_default_prefix: "regents_app"

config :regents, :sprite_provider, Regents.Formation.SpritesHttpProvider
config :regents, :sprites, base_url: "https://api.sprites.dev", token: nil
config :regents, :agent_verification_client, Regents.AgentAuth.SiwaHttpVerificationClient
config :regents, :siwa, base_url: nil, audience: nil, activity_read_token: nil
config :regents, :session_bootstrap_rate_limit, limit: 30, window_seconds: 300

# Rate limits key on the direct peer. Production turns on Fly's client header.
config :regents, :behind_fly_proxy, false

config :regents, :agent_pairing_clock, &DateTime.utc_now/0
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

# The shared staking reading warms at boot and refreshes once a minute without
# a visitor. Background and signed-in requests share the same allowance and
# the ten-second minimum between refreshes.
config :regents, :staking_snapshot_boot_read, true
config :regents, :staking_snapshot_refresh_interval_ms, 60_000
config :regents, :staking_shared_refreshes_per_minute, 6
config :regents, :staking_snapshot_clock, &Regents.Staking.SnapshotCache.monotonic_ms/0

config :regents, :session_options,
  store: :cookie,
  key: "_regents_key",
  signing_salt: "OLoeAaio",
  same_site: "Lax",
  secure: false,
  http_only: true

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
