import Config

config :ash_platform, AshPlatformWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Requests and outcomes are logged; database queries and debug detail are not.
config :logger, level: :info
