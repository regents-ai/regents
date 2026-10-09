import Config
config :regents, :local_showcase, true
port = String.to_integer(System.get_env("PORT", "4002"))

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :regents, RegentsWeb.Endpoint,
  url: [host: "127.0.0.1", port: port],
  http: [ip: {127, 0, 0, 1}, port: port],
  check_origin: ["http://127.0.0.1:#{port}"],
  secret_key_base: "ylCJZnscmD6l7Ykq52GK0o6GrbPmb8374FAcei9yvkWU1ww5Nv+S2v/Z7ihcqZd2",
  server: System.get_env("REGENTS_BROWSER_TEST") == "1"

# Browser test servers run side by side, so each one's metrics take any free port.
config :regents, :metrics_listener, ip: {127, 0, 0, 1}, port: 0

config :regents, :privy_verifier, Regents.TestPrivyVerifier
config :regents, :staking_chain_client, Regents.TestStakingChainClient
config :regents, :chain_client, Regents.TestChainClient
config :regents, :staking_price_http_client, Regents.TestStakingPriceHttpClient

# Tests queue refreshes explicitly. Only a configured browser test server enables
# the automatic staking jobs; Oban still uses the test worker/transport settings.
config :regents, :staking_snapshot_refresh_enabled, System.get_env("REGENTS_BROWSER_TEST") == "1"

config :regents, :redemption_chain_client, Regents.TestRedemptionChainClient
config :regents, :opensea_http_client, Regents.TestOpenSeaHttpClient
config :regents, :opensea_api_key, "test-only-key"
config :regents, :sprite_provider, Regents.TestSpriteProvider

config :regents, :siwa,
  base_url: "https://siwa.test",
  activity_read_token: "test-activity-read-token"

# Agent requests are verified by stubs each test sets.
config :regent_agents,
  siwa: [url: "https://siwa.test", audience: "regents-test"],
  req_options: [plug: {Req.Test, RegentAgents.Broker}]

# Reads from the sign-in service answer from stubs each test sets.
config :regents, :siwa_req_options, plug: {Req.Test, Regents.Siwa}
config :regents, :database_startup_enabled, true

# Jobs are queued, never run, unless a test runs one itself.
config :regents, Oban, testing: :manual

# ENS lookups answer from a stubbed mainnet whose replies are chosen by the
# wallet asking, so no test reaches a real endpoint.
config :regents, :ethereum_read_rpc_url, "https://ethereum.test.invalid"
config :regents, :ethereum_rpc_module, Regents.TestEnsChainClient
config :regents, :ens_lookup_deadline_ms, 200
config :regents, :ens_avatar_http_client, Regents.TestEnsAvatarHttpClient
config :regents, :ens_avatar_deadline_ms, 200

# Every test case here reaches one node holding one anonymous bootstrap budget,
# and one budget of Base readings, for the loopback address they all share, so
# the release-sized allowances are raised rather than let unrelated cases spend
# one another's. The focused tests restore the release limits themselves.
config :regents, :session_bootstrap_rate_limit, limit: 100_000, window_seconds: 300
config :regents, :chain_read_rate_limit, limit: 100_000, window_seconds: 60

# Tests key rate limits as production does, behind Fly's proxy.
config :regents, :behind_fly_proxy, true

config :regents, Regents.Repo,
  username: System.get_env("USER"),
  password: nil,
  hostname: "127.0.0.1",
  port: 5432,
  database: "regents#{System.get_env("MIX_TEST_PARTITION")}_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  # A case that sends two callers at one row shares one sandboxed connection
  # between them, so the second caller waits while the first one holds it. The
  # sandbox drops a waiting caller once it has waited longer than twice
  # :queue_target, and it looks for callers to drop once every :queue_interval,
  # which is one second. At the default target of 50ms that abandons a caller
  # after a tenth of a second, and the case then fails on a checkout error
  # rather than on anything it set out to prove. The 1_000ms below lets a
  # caller wait two seconds instead. Across 180 raced callers on a machine held
  # at a load average of 24, the longest any of them held the connection was
  # 70ms, so a tenth of a second leaves almost no room and two seconds leaves
  # plenty.
  queue_target: 1_000

config :ash, :disable_async?, true
config :ash, :missed_notifications, :ignore

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
