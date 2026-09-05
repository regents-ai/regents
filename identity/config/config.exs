import Config
config :regent_identity, ash_domains: [RegentIdentity]
if config_env() == :test, do: import_config("test.exs")
