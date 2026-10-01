import Config

config :regent_allowance, repo: RegentAllowance.TestRepo, site: "test"

config :regent_allowance, RegentAllowance.TestRepo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_allowance_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 8

config :logger, level: :warning
