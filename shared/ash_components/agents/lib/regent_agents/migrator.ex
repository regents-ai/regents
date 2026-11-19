defmodule RegentAgents.MigrationRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :regent_agents, adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, config),
    do: {:ok, Keyword.put(config, :migration_source, "schema_migrations")}
end

defmodule RegentAgents.Migrator do
  @moduledoc """
  Explicitly migrates the shared agent schema using a separate ledger and
  connection. Invoke from Regents' release preparation only. Merely including
  this package never starts a repository or runs migrations.
  """

  @doc "Checks pairing-history prerequisites without applying shared migrations."
  @spec require_pairing_history!(module()) :: :ok
  def require_pairing_history!(repo) do
    %{rows: [[ready?]]} =
      Ecto.Adapters.SQL.query!(repo, """
      SELECT
        EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
          JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'regent_agents' AND c.relname = 'pairing_history'
            AND a.attname = 'revoked_at' AND NOT a.attisdropped)
        AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
          JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'regent_agents' AND c.relname = 'paired_agents'
            AND t.tgname = 'retain_pairing_episode'
            AND NOT t.tgisinternal AND t.tgenabled IN ('O', 'A'))
      """)

    unless ready?,
      do:
        raise(
          "Signed agent access requires the separately approved shared Agents pairing-history migration before deployment"
        )

    :ok
  end

  def up(repo) do
    options =
      repo.config()
      |> Keyword.drop([:name, :telemetry_prefix, :default_prefix, :migration_default_prefix])
      |> Keyword.merge(
        migration_source: "schema_migrations",
        pool: DBConnection.ConnectionPool,
        pool_size: 2
      )

    case RegentAgents.MigrationRepo.start_link(options) do
      {:ok, pid} ->
        try do
          Ecto.Adapters.SQL.query!(
            RegentAgents.MigrationRepo,
            "CREATE SCHEMA IF NOT EXISTS regent_agents",
            []
          )

          Ecto.Migrator.run(
            RegentAgents.MigrationRepo,
            Application.app_dir(:regent_agents, "priv/repo/migrations"),
            :up,
            all: true,
            prefix: "regent_agents"
          )
        after
          Supervisor.stop(pid)
        end

      {:error, _reason} ->
        raise "Unable to start the dedicated agents migration connection"
    end
  end
end
