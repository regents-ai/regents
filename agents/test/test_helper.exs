ExUnit.start()
name = Keyword.fetch!(RegentAgents.TestRepo.config(), :database)

unless Regex.match?(~r/^regent_agents_test_[a-z0-9_]+$/, name),
  do: raise("refusing unowned database name")

{:ok, _} = RegentAgents.TestRepo.start_link()
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: RegentAgents.TestPubSub)
{:ok, _} = RegentAgents.Listener.start_link([])

Ecto.Migrator.run(
  RegentAgents.TestRepo,
  [{0, RegentAgents.TestRepo.AshFunctions}],
  :up,
  all: true,
  log: false
)

RegentAgents.Migrator.up(RegentAgents.TestRepo)

Ecto.Adapters.SQL.Sandbox.mode(RegentAgents.TestRepo, :manual)
