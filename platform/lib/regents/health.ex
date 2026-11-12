defmodule Regents.Health do
  @moduledoc """
  Whether the site's own database answers, for the health check, and whether
  every migration this release carries is applied.
  """

  # A running server alone does not make the site ready: read one of the site's
  # own tables without returning rows. The timeout is below Fly's two-second
  # health deadline, and no error or connection detail leaves this module. The
  # schema is the repository's own configured name, never request input.
  # sobelow_skip ["SQL.Query"]
  @doc "True when the site's own table answers within a second."
  def database_ready? do
    case Ecto.Adapters.SQL.query(
           Regents.Repo,
           "SELECT 1 FROM \"#{Regents.Repo.default_prefix()}\".session_authorities LIMIT 0",
           [],
           timeout: 1_000,
           log: false
         ) do
      {:ok, _result} -> true
      {:error, _error} -> false
    end
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end

  @doc """
  True when every migration file this release carries is recorded in the site's
  own schema. It only reads: no lock, and it never creates the ledger. A
  database that does not answer is `false`.
  """
  def migrations_applied? do
    Regents.Repo
    |> Ecto.Migrator.migrations([Application.app_dir(:regents, "priv/repo/migrations")],
      prefix: Regents.Repo.default_prefix(),
      skip_table_creation: true,
      migration_lock: false,
      timeout: 1_000,
      log: false
    )
    |> Enum.all?(&match?({:up, _version, _name}, &1))
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end
end
