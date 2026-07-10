import Config

if config_env() == :prod do
  config :ash_platform, AshPlatformWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end
