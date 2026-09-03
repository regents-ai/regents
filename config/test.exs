import Config

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
config :ash_platform, :staking_chain_client, AshPlatform.TestStakingChainClient

# No ExUnit run reads Base at startup. A case that wants a shared reading asks
# for one, which is the same path a signed-in visitor takes. The browser server
# does take its one reading at startup, because a person opening the page in a
# browser should meet the warm server a release gives them.
config :ash_platform,
       :staking_snapshot_boot_read,
       System.get_env("ASH_PLATFORM_BROWSER_TEST") == "1"

config :ash_platform, :redemption_chain_client, AshPlatform.TestRedemptionChainClient
config :ash_platform, :wallet_transaction_observer, AshPlatform.TestWalletTransactionObserver
config :ash_platform, :opensea_http_client, AshPlatform.TestOpenSeaHttpClient
config :ash_platform, :opensea_api_key, "test-only-key"
config :ash_platform, :sprite_provider, AshPlatform.TestSpriteProvider
config :ash_platform, :marimo_exporter, AshPlatform.TestMarimoArtifact.UvxExporter

config :ash_platform,
       :agent_verification_client,
       AshPlatform.AgentAuth.DeterministicVerificationClient

config :ash_platform, :siwa, base_url: "https://siwa.test", audience: "ash-platform-test"
config :ash_platform, :database_startup_enabled, true

# The Base log ledger never runs under test: the tests drive its handler
# directly against a fake endpoint, and nothing in the shell can turn it on.
config :ash_platform, :autolaunch_indexer_rpc_url, nil

config :ash_platform,
       :autolaunch_indexer_http_client,
       AshPlatform.TestAutolaunchIndexerChainClient

# ENS lookups answer from a stubbed mainnet whose replies are chosen by the
# wallet asking, so no test reaches a real endpoint.
config :ash_platform, :ethereum_read_rpc_url, "https://ethereum.test.invalid"
config :ash_platform, :ethereum_rpc_module, AshPlatform.TestEnsChainClient
config :ash_platform, :ens_lookup_deadline_ms, 200
config :ash_platform, :ens_avatar_http_client, AshPlatform.TestEnsAvatarHttpClient
config :ash_platform, :ens_avatar_deadline_ms, 200

# Every test case here reaches one node holding one anonymous bootstrap budget
# for the loopback address they all share, so the release-sized allowance is
# raised rather than let unrelated cases spend one another's. The focused
# controller tests restore the release 30/300 themselves.
config :ash_platform, :session_bootstrap_rate_limit, limit: 100_000, window_seconds: 300

# The subject wallet browser proof needs a Base answer without a provider, a
# wallet or a chain call. Ordinary ExUnit cases install and restore this client
# themselves, so only the Playwright server process selects it here.
if System.get_env("ASH_PLATFORM_BROWSER_TEST") == "1" do
  config :ash_platform,
         :autolaunch_subject_wallet_chain_client,
         AshPlatform.TestAutolaunchSubjectWalletChainClient

  config :ash_platform,
         :autolaunch_launch_chain_client,
         AshPlatform.TestAutolaunchLaunchChainClient

  config :ash_platform,
         :wallet_transaction_observer,
         AshPlatform.TestBrowserWalletTransactionObserver
end

config :ash_platform, :notebook_origins, ["http://127.0.0.1:4003"]

config :ash_platform,
       :notebook_static_server,
       if(System.get_env("ASH_PLATFORM_BROWSER_TEST") == "1",
         do: [scheme: :http, ip: {127, 0, 0, 1}, port: 4003, startup_log: false],
         else: false
       )

config :ash_platform, AshPlatform.Repo,
  username: System.get_env("USER"),
  password: nil,
  hostname: "127.0.0.1",
  port: 5432,
  database: "ash_platform#{System.get_env("MIX_TEST_PARTITION")}_test",
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
