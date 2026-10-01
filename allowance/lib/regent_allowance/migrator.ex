defmodule RegentAllowance.MigrationRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :regent_allowance, adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, config),
    do: {:ok, Keyword.put(config, :migration_source, "schema_migrations")}
end

defmodule RegentAllowance.Migrator do
  @moduledoc """
  Explicitly migrates the shared allowance schema using a separate ledger and
  connection. Invoke from Regents' release preparation only. Merely including
  this package never starts a repository or runs migrations.
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

    case RegentAllowance.MigrationRepo.start_link(options) do
      {:ok, pid} ->
        try do
          Ecto.Adapters.SQL.query!(
            RegentAllowance.MigrationRepo,
            "CREATE SCHEMA IF NOT EXISTS regent_allowance",
            []
          )

          Ecto.Migrator.run(
            RegentAllowance.MigrationRepo,
            Application.app_dir(:regent_allowance, "priv/repo/migrations"),
            :up,
            all: true,
            prefix: "regent_allowance"
          )
        after
          Supervisor.stop(pid)
        end

      {:error, _reason} ->
        raise "Unable to start the dedicated allowance migration connection"
    end
  end
end
