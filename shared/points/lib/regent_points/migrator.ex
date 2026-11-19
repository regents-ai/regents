defmodule RegentPoints.MigrationRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :regent_points, adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, config),
    do: {:ok, Keyword.put(config, :migration_source, "schema_migrations")}
end

defmodule RegentPoints.Migrator do
  @moduledoc """
  Migrates the `regent_points` schema over a dedicated connection, with its
  own migration ledger inside that schema. A site runs it locally; in
  production only Regents runs it, from its release preparation. Including
  the library never starts a repository or runs a migration.

  The canonical `regent_names.platform_human_users` table must already exist.
  """

  @spec up(module()) :: :ok
  def up(repo) do
    options =
      repo.config()
      |> Keyword.drop([:name, :telemetry_prefix, :default_prefix, :migration_default_prefix])
      |> Keyword.merge(
        migration_source: "schema_migrations",
        pool: DBConnection.ConnectionPool,
        pool_size: 2
      )

    case RegentPoints.MigrationRepo.start_link(options) do
      {:ok, pid} ->
        try do
          Ecto.Adapters.SQL.query!(
            RegentPoints.MigrationRepo,
            "CREATE SCHEMA IF NOT EXISTS regent_points",
            []
          )

          Ecto.Migrator.run(
            RegentPoints.MigrationRepo,
            Application.app_dir(:regent_points, "priv/repo/migrations"),
            :up,
            all: true,
            prefix: "regent_points"
          )

          :ok
        after
          Supervisor.stop(pid)
        end

      {:error, _reason} ->
        raise "Unable to start the dedicated Points migration connection"
    end
  end
end
