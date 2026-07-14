# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mime, :types, %{"application/yaml" => ["yaml"]}

config :ash_platform,
  ash_domains: [
    AshPlatform.Accounts,
    AshPlatform.Billing,
    AshPlatform.Discussions,
    AshPlatform.Formation,
    AshPlatform.Techtree,
    AshPlatform.Autolaunch,
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

config :ash_platform, :privy, clock: fn -> System.system_time(:second) end
config :ash_platform, :sprite_provider, AshPlatform.Formation.SpritesHttpProvider
config :ash_platform, :sprites, base_url: "https://api.sprites.dev", token: nil
config :ash_platform, :base_read_rpc_url, "https://base-rpc.publicnode.com"
config :ash_platform, :notebook_origins, ["https://notebooks.regents.sh"]
config :ash_platform, :notebook_static_server, false

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
      ~w(js/app.ts js/privy_bridge.tsx --bundle --splitting --format=esm --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
