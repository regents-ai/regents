ExUnit.start(exclude: [external: true])
AshPlatform.LocalDatabaseFixture.ensure_human_accounts!()
Ecto.Adapters.SQL.Sandbox.mode(AshPlatform.Repo, :manual)
