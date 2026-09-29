import Config

config :regent_agents,
  repo: RegentAgents.TestRepo,
  pubsub: RegentAgents.TestPubSub,
  account: {RegentAgents.Test.Site, :account},
  siwa: [url: "https://siwa.test", audience: "test"],
  req_options: [plug: {Req.Test, RegentAgents.Broker}]

config :regent_agents, RegentAgents.TestRepo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_agents_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 8

config :logger, level: :warning

# No resource here has notifiers; transactions report none.
config :ash, :missed_notifications, :ignore
