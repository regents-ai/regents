import Config

require Logger

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  release: System.get_env("SENTRY_RELEASE"),
  environment_name: System.get_env("SENTRY_ENVIRONMENT", to_string(config_env()))

config :regents, :privy,
  app_id: System.get_env("PRIVY_APP_ID"),
  verification_key: System.get_env("PRIVY_VERIFICATION_KEY")

# Without its Privy settings a local server answers every page while nobody can
# sign in, so it refuses to start. A worktree holds no settings files of its own.
# Other mix tasks, such as migrations and code generation, run without them.
if config_env() == :dev and Phoenix.Endpoint.server?(:regents, RegentsWeb.Endpoint) do
  for name <- ~w(PRIVY_APP_ID PRIVY_VERIFICATION_KEY), System.get_env(name, "") == "" do
    raise """
    #{name} is not set, so nobody could sign in. Start the site with its settings loaded:
    direnv exec <main checkout>/platform mix phx.server
    """
  end
end

# The browser acceptance server names a test-only Privy app. Production can
# never take this branch.
if config_env() == :test and System.get_env("REGENTS_BROWSER_TEST") == "1" do
  config :regents, :privy, app_id: "browser-test-public-id", verification_key: nil
end

if config_env() != :test do
  config :regents, :opensea_api_key, System.get_env("OPENSEA_API_KEY")
end

config :regent_sprites, token: System.get_env("SPRITES_TOKEN")

if config_env() != :test do
  config :regents, :siwa,
    base_url: System.get_env("SIWA_SERVER_URL"),
    activity_read_token: System.get_env("SIWA_ACTIVITY_READ_TOKEN")

  config :regent_agents, :siwa,
    url: System.get_env("SIWA_SERVER_URL"),
    audience: System.get_env("SIWA_AUDIENCE")
end

# Production must say out loud whether the product surfaces are open. Anything
# but "on" keeps them closed, so a typo closes rather than opens.
app_surfaces_setting =
  case {config_env(), System.get_env("REGENTS_APP_SURFACES")} do
    {:prod, nil} ->
      raise ~s(REGENTS_APP_SURFACES must be set to "on" or "off")

    {_env, nil} ->
      "on"

    {_env, setting} ->
      setting
  end

app_surfaces? = app_surfaces_setting == "on"

config :regents, :app_surfaces, app_surfaces?

Logger.info("App surfaces #{if app_surfaces?, do: "enabled", else: "disabled"}")

# The signed wallet's ENS name and picture are read from Ethereum mainnet. The
# test environment owns this setting outright, and only the host is logged
# because provider URLs carry the API key.
if config_env() != :test do
  ethereum_read_rpc_url = String.trim(System.get_env("ETHEREUM_READ_RPC_URL", ""))

  if ethereum_read_rpc_url != "" do
    config :regents, :ethereum_read_rpc_url, ethereum_read_rpc_url

    Logger.info("Ethereum read endpoint host #{URI.parse(ethereum_read_rpc_url).host}")
  end
end

# The Privy accounts that may give Credits and handle refunds, comma separated.
if admins = System.get_env("REGENT_CREDITS_ADMINS") do
  config :regent_credits,
    admins: admins |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
end

migrating? = System.get_env("REGENTS_RELEASE_COMMAND") == "migrate"

database_config =
  if config_env() == :prod and migrating? do
    Regents.DatabaseConfig.release_config!()
  else
    Regents.DatabaseConfig.runtime_config!(config_env())
  end

if database_config do
  config :regents, :database_startup_enabled, true
  config :regents, Regents.Repo, database_config
end

# Local Stake and Redeem read the same Base endpoint as production when
# `BASE_READ_RPC_URL` names one; without it the public default in `config.exs`
# stands. Only the host is logged, because provider URLs carry the API key.
if config_env() == :dev do
  config :regents,
         :staking_snapshot_refresh_enabled,
         System.get_env("STAKING_SNAPSHOT_REFRESH_ENABLED") == "true"

  base_read_rpc_url = String.trim(System.get_env("BASE_READ_RPC_URL", ""))

  if base_read_rpc_url != "" do
    config :regents, :base_read_rpc_url, base_read_rpc_url

    Logger.info("Development Base read endpoint host #{URI.parse(base_read_rpc_url).host}")
  end
end

if config_env() == :prod do
  # Stake and Redeem read one canonical `safe` Base block through this endpoint.
  # Development has a default in `config.exs`; production must say which
  # endpoint it trusts, so a missing value stops the boot instead of quietly
  # reading a public one.
  config :regents, :base_read_rpc_url, System.fetch_env!("BASE_READ_RPC_URL")

  config :regents, :session_options, secure: true, http_only: true

  unless migrating? do
    host = String.trim(System.fetch_env!("PHX_HOST"))
    secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

    if host == "" do
      raise "PHX_HOST must not be empty"
    end

    if byte_size(secret_key_base) < 64 do
      raise "SECRET_KEY_BASE must be at least 64 bytes"
    end

    config :regents, RegentsWeb.Endpoint,
      server: true,
      url: [host: host, port: 443, scheme: "https"],
      http: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: String.to_integer(System.get_env("PORT", "4000"))
      ],
      secret_key_base: secret_key_base
  end
end
