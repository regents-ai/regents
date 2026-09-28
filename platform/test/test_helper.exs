ExUnit.start(exclude: [external: true])
Regents.LocalDatabaseFixture.ensure_human_accounts!()
Ecto.Adapters.SQL.Sandbox.mode(Regents.Repo, :manual)
