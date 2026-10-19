# Logs from a passing test stay hidden; a failing test prints its own.
ExUnit.start(exclude: [external: true], capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Regents.Repo, :manual)
