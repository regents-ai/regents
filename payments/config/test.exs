import Config

config :regent_payments,
  repo: RegentPayments.TestRepo,
  site: "test",
  offers: [RegentPayments.Test.DirectOffer, RegentPayments.Test.PublishOffer],
  payment_chain: %{name: "Base", rpc_url: "https://mainnet.base.org"},
  wallet_proof: [name: "Regent test", version: "1", endpoint: RegentPayments.Test.Endpoint]

config :regent_payments, RegentPayments.TestRepo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_payments_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 8

config :logger, level: :warning

# The facilitator's address is the loopback stand-in each payment test starts.
config :regent_payments, RegentPayments.Facilitator, receive_timeout_ms: 2_000
