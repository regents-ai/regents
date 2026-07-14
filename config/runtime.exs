import Config

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

database_config =
  if config_env() == :prod and System.get_env("ASH_PLATFORM_RELEASE_COMMAND") == "migrate" do
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

  config :ash_platform, AshPlatformWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end
