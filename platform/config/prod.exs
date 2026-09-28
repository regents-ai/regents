import Config

config :regents, RegentsWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# Every request reaches production through Fly's proxy, which sets Fly-Client-IP.
config :regents, :behind_fly_proxy, true

# The private port fly.toml names under [metrics]; Fly routes no public traffic to it.
config :regents, :metrics_listener, ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 9091

# Requests and outcomes are logged; database queries and debug detail are not.
config :logger, level: :info
