import Config

# Every page is served over HTTPS and says so with Strict-Transport-Security. Fly's
# proxy ends TLS and says so in `x-forwarded-proto`. Fly's health check reaches the
# machine directly over plain HTTP, so its path is answered rather than redirected.
# `:force_ssl` is read when the endpoint compiles, so it lives here.
config :regents, RegentsWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [rewrite_on: [:x_forwarded_proto], exclude: [paths: ["/healthz"]]]

# Every request reaches production through Fly's proxy, which sets Fly-Client-IP.
config :regents, :behind_fly_proxy, true

# The private port fly.toml names under [metrics]; Fly routes no public traffic to it.
config :regents, :metrics_listener, ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 9091

# Requests and outcomes are logged; database queries and debug detail are not.
config :logger, level: :info
