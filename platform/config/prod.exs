import Config

# Every page is served over HTTPS and says so with Strict-Transport-Security.
# Fly's proxy ends TLS and says so in `x-forwarded-proto`, which `:rewrite_on`
# reads. Fly's health check reaches the machine directly over plain HTTP with
# `Host: localhost` (fly.toml), and is answered rather than redirected, so
# `:exclude` sits inside `:force_ssl`, where Plug.SSL reads it. `:force_ssl` is
# read when the endpoint compiles, so it lives here and not in runtime.exs.
config :regents, RegentsWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [rewrite_on: [:x_forwarded_proto], exclude: ["localhost", "127.0.0.1"]]

# Every request reaches production through Fly's proxy, which sets Fly-Client-IP.
config :regents, :behind_fly_proxy, true

# The private port fly.toml names under [metrics]; Fly routes no public traffic to it.
config :regents, :metrics_listener, ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 9091

# Requests and outcomes are logged; database queries and debug detail are not.
config :logger, level: :info
