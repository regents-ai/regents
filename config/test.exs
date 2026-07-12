import Config

config :ash_platform, :database_startup_enabled, true
config :ash_platform, :notebook_origins, ["http://127.0.0.1:4003"]

config :ash_platform, AshPlatform.Repo,
  hostname: "127.0.0.1",
  database: "ash_platform_test",
  username: System.get_env("USER"),
  password: nil,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :ash, :disable_async?, true
config :ash, :missed_notifications, :ignore

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ash_platform, AshPlatformWeb.Endpoint,
  url: [host: "127.0.0.1", port: 4002],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  check_origin: ["http://127.0.0.1:4002"],
  secret_key_base: "ylCJZnscmD6l7Ykq52GK0o6GrbPmb8374FAcei9yvkWU1ww5Nv+S2v/Z7ihcqZd2",
  server: System.get_env("ASH_PLATFORM_BROWSER_TEST") == "1"

config :ash_platform, :content_provider, AshPlatform.TestContentProvider
config :ash_platform, :privy_verifier, AshPlatform.TestPrivyVerifier

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
