defmodule RegentIdentity.MigrationRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :regent_identity, adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, config),
    do: {:ok, Keyword.put(config, :migration_source, "schema_migrations")}
end

defmodule RegentIdentity.Migrator do
  @moduledoc """
  Explicitly migrates the shared schema using a separate ledger and connection.
  Invoke once from Regents' release preparation, after database reconciliation.
  Merely including this package never starts a repository or runs migrations.
  """

  def up(repo) do
    options =
      repo.config()
      |> Keyword.drop([:name, :telemetry_prefix, :default_prefix, :migration_default_prefix])
      |> Keyword.merge(
        migration_source: "schema_migrations",
        pool: DBConnection.ConnectionPool,
        pool_size: 2
      )

    case RegentIdentity.MigrationRepo.start_link(options) do
      {:ok, pid} ->
        try do
          Ecto.Adapters.SQL.query!(
            RegentIdentity.MigrationRepo,
            "CREATE SCHEMA IF NOT EXISTS regent_identity",
            []
          )

          Ecto.Migrator.run(
            RegentIdentity.MigrationRepo,
            Application.app_dir(:regent_identity, "priv/repo/migrations"),
            :up,
            all: true,
            prefix: "regent_identity"
          )
        after
          Supervisor.stop(pid)
        end

      {:error, _reason} ->
        raise "Unable to start the dedicated identity migration connection"
    end
  end
end
