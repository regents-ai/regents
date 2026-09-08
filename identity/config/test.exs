import Config
config :regent_identity, repo: RegentIdentity.TestRepo

config :regent_identity, RegentIdentity.TestRepo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: System.fetch_env!("REGENT_IDENTITY_TEST_DATABASE"),
  migration_source: "regent_identity_schema_migrations",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 8

config :logger, level: :warning
