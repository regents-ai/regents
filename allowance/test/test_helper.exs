ExUnit.start()
name = Keyword.fetch!(RegentAllowance.TestRepo.config(), :database)

unless Regex.match?(~r/^regent_allowance_test_[a-z0-9_]+$/, name),
  do: raise("refusing unowned database name")

{:ok, _} = RegentAllowance.TestRepo.start_link()
RegentAllowance.Migrator.up(RegentAllowance.TestRepo)
Ecto.Adapters.SQL.Sandbox.mode(RegentAllowance.TestRepo, :manual)
