ExUnit.start()
name = System.fetch_env!("REGENT_IDENTITY_TEST_DATABASE")

unless Regex.match?(~r/^regent_identity_test_[a-z0-9_]+$/, name),
  do: raise("refusing unowned database name")

{:ok, _} = RegentIdentity.TestRepo.start_link()

Ecto.Migrator.run(RegentIdentity.TestRepo, Path.expand("../priv/repo/migrations", __DIR__), :up,
  all: true
)

Ecto.Adapters.SQL.Sandbox.mode(RegentIdentity.TestRepo, :manual)
