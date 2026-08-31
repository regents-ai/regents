import Config

require Logger

privy_verification_key =
  case System.get_env("PRIVY_VERIFICATION_KEY") do
    nil ->
      nil

    value ->
      value
      |> String.replace("\\r\\n", "\n")
      |> String.replace("\\n", "\n")
  end

config :ash_platform, :privy,
  app_id: System.get_env("PRIVY_APP_ID"),
  verification_key: privy_verification_key

admin_wallet_addresses =
  "REGENT_ADMIN_WALLET_ADDRESSES"
  |> System.get_env("")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))

config :ash_platform, :admin_wallet_addresses, admin_wallet_addresses

# This one-time protected route is closed unless a deployment explicitly says
# "on". No public identifier or verifier secret is logged.
regents_club_metadata_cutover? =
  System.get_env("ASH_PLATFORM_REGENTS_CLUB_METADATA_CUTOVER") == "on"

config :ash_platform, :regents_club_metadata_cutover, regents_club_metadata_cutover?

config :ash_platform,
       :regents_club_privy_origin_canary,
       System.get_env("ASH_PLATFORM_REGENTS_CLUB_PRIVY_ORIGIN_CANARY") == "passed"

config :ash_platform,
       :regents_club_media_full_corpus_attestation,
       System.get_env("ASH_PLATFORM_REGENTS_CLUB_MEDIA_FULL_CORPUS_SHA256")

Logger.info(
  "Regents Club metadata cutover #{if regents_club_metadata_cutover?, do: "enabled", else: "disabled"}"
)

# The browser acceptance server uses the same protected flow with deterministic
# test-only session, media and chain implementations. Production can never take
# this branch.
if config_env() == :test and System.get_env("ASH_PLATFORM_BROWSER_TEST") == "1" do
  config :ash_platform, :regents_club_metadata_cutover, true
  config :ash_platform, :regents_club_privy_origin_canary, true

  config :ash_platform,
         :regents_club_media_full_corpus_attestation,
         "356352b67b6338ec0b19595d1c0140bf8052756a793163a95a3071ef25a52789"

  config :ash_platform,
         :regents_club_chain_client,
         AshPlatform.TestRegentsClubChainClient

  config :ash_platform,
         :regents_club_media_probe_module,
         AshPlatform.TestRegentsClubChainClient

  config :ash_platform, :privy, app_id: "browser-test-public-id", verification_key: nil
end

if config_env() != :test do
  config :ash_platform, :opensea_api_key, System.get_env("OPENSEA_API_KEY")
end

config :ash_platform, :sprites,
  base_url: "https://api.sprites.dev",
  token: System.get_env("SPRITES_TOKEN")

config :ash_platform, :siwa,
  base_url: System.get_env("SIWA_SERVER_URL"),
  audience: System.get_env("SIWA_AUDIENCE")

config :ash_platform, :techtree_publication_rate_limit,
  limit: String.to_integer(System.get_env("TECHTREE_PUBLICATION_RATE_LIMIT", "10")),
  window_seconds:
    String.to_integer(System.get_env("TECHTREE_PUBLICATION_RATE_WINDOW_SECONDS", "60"))

# Production must say out loud whether the product surfaces are open. Anything
# but "on" keeps them closed, so a typo closes rather than opens.
app_surfaces_setting =
  case {config_env(), System.get_env("ASH_PLATFORM_APP_SURFACES")} do
    {:prod, nil} ->
      raise ~s(ASH_PLATFORM_APP_SURFACES must be set to "on" or "off")

    {_env, nil} ->
      "on"

    {_env, setting} ->
      setting
  end

app_surfaces? = app_surfaces_setting == "on"

config :ash_platform, :app_surfaces, app_surfaces?

Logger.info("App surfaces #{if app_surfaces?, do: "enabled", else: "disabled"}")

# Autolaunch is switched separately and stays closed unless a deployment says
# "on". Only the test environment opens it without being asked.
autolaunch_surfaces? =
  case {config_env(), System.get_env("ASH_PLATFORM_AUTOLAUNCH_SURFACES")} do
    {:test, nil} -> true
    {_env, setting} -> setting == "on"
  end

config :ash_platform, :autolaunch_surfaces, autolaunch_surfaces?

# The Base log ledger reads its own dedicated endpoint, separate from the
# simple-read RPC. The test environment owns this setting outright so a shell
# that exports one cannot start an indexer under a test run.
if config_env() != :test do
  config :ash_platform,
         :autolaunch_indexer_rpc_url,
         System.get_env("AUTOLAUNCH_INDEXER_RPC_URL")
end

migrating? = System.get_env("ASH_PLATFORM_RELEASE_COMMAND") == "migrate"

database_config =
  if config_env() == :prod and migrating? do
    AshPlatform.DatabaseConfig.release_config!()
  else
    AshPlatform.DatabaseConfig.runtime_config!(config_env())
  end

if database_config do
  config :ash_platform, :database_startup_enabled, true
  config :ash_platform, AshPlatform.Repo, database_config
end

if config_env() == :prod do
  # Stake and Redeem read one canonical `safe` Base block through this endpoint.
  # Development has a default in `config.exs`; production must say which
  # endpoint it trusts, so a missing value stops the boot instead of quietly
  # reading a public one.
  config :ash_platform, :base_read_rpc_url, System.fetch_env!("BASE_READ_RPC_URL")

  config :ash_platform, :session_options, secure: true, http_only: true

  unless migrating? do
    host = String.trim(System.fetch_env!("PHX_HOST"))
    secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

    if host == "" do
      raise "PHX_HOST must not be empty"
    end

    if byte_size(secret_key_base) < 64 do
      raise "SECRET_KEY_BASE must be at least 64 bytes"
    end

    config :ash_platform, AshPlatformWeb.Endpoint,
      server: true,
      url: [host: host, port: 443, scheme: "https"],
      http: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: String.to_integer(System.get_env("PORT", "4000"))
      ],
      secret_key_base: secret_key_base
  end
end
