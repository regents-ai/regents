import Config

privy_verification_key =
  case System.get_env("PRIVY_VERIFICATION_KEY") do
    nil -> nil
    value -> value |> String.replace("\\r\\n", "\n") |> String.replace("\\n", "\n")
  end

config :ash_platform, :privy,
  app_id: System.get_env("PRIVY_APP_ID"),
  verification_key: privy_verification_key

if config_env() == :prod do
  config :ash_platform, :session_options, secure: true, http_only: true

  config :ash_platform, AshPlatformWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end
