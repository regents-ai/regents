defmodule Regents.Health do
  @moduledoc """
  Whether the site's own database answers, for the health check, and whether
  every migration this release carries is applied.
  """

  # A running server alone does not make the site ready: read one of the site's
  # own tables without returning rows. It is a public one, the Stake page's
  # saved reading, which the read-only venue's login may read too. The timeout is
  # below Fly's two-second health deadline, and no error or connection detail
  # leaves this module. The schema is the repository's own configured name,
  # never request input.
  # sobelow_skip ["SQL.Query"]
  @doc "True when the site's own table answers within a second."
  def database_ready? do
    case Ecto.Adapters.SQL.query(
           Regents.Repo,
           "SELECT 1 FROM \"#{Regents.Repo.default_prefix()}\".staking_protocol_readings LIMIT 0",
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
  True when every migration file this release carries is recorded in its area's
  own ledger. `areas` is `Regents.Products.migration_areas/0`, the site's own
  schema and each product's; the caller passes it, since the product list depends
  on this module's boundary and not the other way. It only reads: no lock, and it
  never creates a ledger. A database that does not answer, or an area without a
  ledger, is `false`.
  """
  def migrations_applied?(areas) do
    Enum.all?(areas, fn {schema, path} ->
      path
      |> Regents.Repo.migrations(schema, timeout: 1_000, log: false)
      |> Enum.all?(&match?({:up, _version, _name}, &1))
    end)
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end
end
