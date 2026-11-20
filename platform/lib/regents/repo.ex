defmodule Regents.Repo do
  use AshPostgres.Repo, otp_app: :regents

  # Regents' own tables live in this schema of the shared database, beside the
  # other products' `autolaunch_app`, `patchbay_app` and `techtree_app`. Resources
  # that read tables owned elsewhere name their schema themselves.
  @schema "regents_app"

  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: ["ash-functions"]
  def default_prefix, do: @schema

  # Ash qualifies reads with `default_prefix/0`; writes and plain Ecto queries take
  # the prefix from here instead. An explicit prefix, such as a resource's own
  # schema, always wins over this default.
  def default_options(_operation), do: [prefix: @schema]

  # PostgreSQL's own catalog (`pg_class`, `pg_namespace`, ...) is never in this
  # schema, so a read of it drops the default above. ErrorTracker's migration
  # reads it.
  def prepare_query(_operation, %{from: %{source: {"pg_" <> _table, nil}}} = query, opts),
    do: {query, Keyword.delete(opts, :prefix)}

  def prepare_query(_operation, query, opts), do: {query, opts}

  @doc """
  Creates `schema` if needed and runs every migration in `path` against it, with
  the ledger at `<schema>.schema_migrations`: this site's own area and each folded
  product's (`Regents.Release`).
  """
  # The schema is one of the release's own fixed names, never input.
  # sobelow_skip ["SQL.Query"]
  def migrate!(path, schema) do
    Ecto.Adapters.SQL.query!(__MODULE__, "CREATE SCHEMA IF NOT EXISTS #{schema}", [])
    Ecto.Migrator.run(__MODULE__, path, :up, all: true, prefix: schema)
  end
end
