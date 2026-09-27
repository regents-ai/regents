import Config

config :ash_platform, AshPlatformWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# The private port fly.toml names under [metrics]; Fly routes no public traffic to it.
config :ash_platform, :metrics_listener, ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 9091

# Requests and outcomes are logged; database queries and debug detail are not.
config :logger, level: :info
