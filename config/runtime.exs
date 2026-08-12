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
