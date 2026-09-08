# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :regent_identity, repo: AshPlatform.Repo, ash_domains: [RegentIdentity]

# Ash 3.33 requires an explicit string length unit. Codepoints match how
# PostgreSQL counts `length()`, so `max_length` bounds stored size; graphemes
# (`:mixed`) do not, because one grapheme can carry unbounded combining marks
# (CVE-2026-82752).
config :ash, default_string_length_count: :codepoints

config :mime, :types, %{"application/yaml" => ["yaml"]}

config :ash_platform,
  local_showcase: false,
  ash_domains: [
    AshPlatform.Names,
    AshPlatform.Accounts,
    AshPlatform.Discussions,
    AshPlatform.Formation,
    AshPlatform.Autolaunch,
    AshPlatform.OpenSea,
    AshPlatform.Redemption,
    AshPlatform.Staking
  ],
  generators: [timestamp_type: :utc_datetime]

config :ash_platform, ecto_repos: [AshPlatform.Repo]

config :ash_platform, AshPlatform.Repo,
  database: "ash_platform_disabled",
  hostname: "127.0.0.1",
  port: 1,
  pool_size: 1

config :ash_platform, :sprite_provider, AshPlatform.Formation.SpritesHttpProvider
config :ash_platform, :sprites, base_url: "https://api.sprites.dev", token: nil
config :ash_platform, :agent_verification_client, AshPlatform.AgentAuth.SiwaHttpVerificationClient
config :ash_platform, :siwa, base_url: nil, audience: nil
config :ash_platform, :session_bootstrap_rate_limit, limit: 30, window_seconds: 300

config :ash_platform, :agent_pairing_clock, &DateTime.utc_now/0
config :ash_platform, :base_read_rpc_url, "https://base-rpc.publicnode.com"
# ENS lives on Ethereum mainnet, which has no public endpoint this product is
# willing to trust: without one named at boot, no name or picture is looked up.
config :ash_platform, :ethereum_read_rpc_url, nil
config :ash_platform, :ethereum_rpc_module, AgentEns.Internal.RPC
config :ash_platform, :ens_lookup_deadline_ms, 4_000
config :ash_platform, :ens_avatar_http_client, AshPlatform.Ens.AvatarHttpClient
config :ash_platform, :ens_avatar_deadline_ms, 2_000
config :ash_platform, :autolaunch_indexer_rpc_url, nil
config :ash_platform, :app_surfaces, true
config :ash_platform, :regents_club_metadata_cutover, false
config :ash_platform, :regents_club_privy_origin_canary, false
config :ash_platform, :regents_club_media_full_corpus_attestation, nil
config :ash_platform, :opensea_api_key, nil
config :ash_platform, :opensea_http_client, AshPlatform.OpenSea.HttpClient
config :ash_platform, :opensea_live_lookups_per_minute, 60
config :ash_platform, :opensea_lookups_per_minute, 6
config :ash_platform, :opensea_holdings_clock, &AshPlatform.OpenSea.HoldingsCache.monotonic_ms/0
# Also bounds how often one address may be reset: once per window.
config :ash_platform, :opensea_holdings_cache_ttl_ms, 15_000

# The shared staking reading warms at boot and refreshes once a minute without
# a visitor. Background and signed-in requests share the same allowance and
# the ten-second minimum between refreshes.
config :ash_platform, :staking_snapshot_boot_read, true
config :ash_platform, :staking_snapshot_refresh_interval_ms, 60_000
config :ash_platform, :staking_shared_refreshes_per_minute, 6
config :ash_platform, :staking_snapshot_clock, &AshPlatform.Staking.SnapshotCache.monotonic_ms/0

config :ash_platform, :session_options,
  store: :cookie,
  key: "_ash_platform_key",
  signing_salt: "OLoeAaio",
  same_site: "Lax",
  secure: false,
  http_only: true

# Configure the endpoint
config :ash_platform, AshPlatformWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AshPlatformWeb.ErrorHTML, json: AshPlatformWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AshPlatform.PubSub,
  live_view: [signing_salt: "RH19ZPg2"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ash_platform: [
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
  tags: %{app: "ash_platform"}

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
