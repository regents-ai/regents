defmodule RegentPayments.MigrationRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :regent_payments, adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, config),
    do: {:ok, Keyword.put(config, :migration_source, "schema_migrations")}
end

defmodule RegentPayments.Migrator do
  @moduledoc """
  Explicitly migrates the shared payment schema using a separate ledger and
  connection. Invoke once from Regents' release preparation, after database
  reconciliation. Merely including this package never starts a repository or
  runs migrations.
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

    case RegentPayments.MigrationRepo.start_link(options) do
      {:ok, pid} ->
        try do
          Ecto.Adapters.SQL.query!(
            RegentPayments.MigrationRepo,
            "CREATE SCHEMA IF NOT EXISTS regent_payments",
            []
          )

          Ecto.Migrator.run(
            RegentPayments.MigrationRepo,
            Application.app_dir(:regent_payments, "priv/repo/migrations"),
            :up,
            all: true,
            prefix: "regent_payments"
          )
        after
          Supervisor.stop(pid)
        end

      {:error, _reason} ->
        raise "Unable to start the dedicated payments migration connection"
    end
  end
end
