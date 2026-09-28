ExUnit.start()
name = Keyword.fetch!(RegentPayments.TestRepo.config(), :database)

unless Regex.match?(~r/^regent_payments_test_[a-z0-9_]+$/, name),
  do: raise("refusing unowned database name")

{:ok, _} = RegentPayments.TestRepo.start_link()

Ecto.Migrator.run(RegentPayments.TestRepo, [{0, RegentPayments.TestRepo.AshFunctions}], :up,
  all: true,
  log: false
)

RegentPayments.Migrator.up(RegentPayments.TestRepo)

Ecto.Adapters.SQL.Sandbox.mode(RegentPayments.TestRepo, :manual)
