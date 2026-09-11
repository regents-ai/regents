defmodule AshPlatform.Repo do
  use AshPostgres.Repo, otp_app: :ash_platform

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

  @doc """
  Creates the product schema if needed and runs every migration in `path`
  against it, with the ledger at `regents_app.schema_migrations`.
  """
  def migrate!(path) do
    Ecto.Adapters.SQL.query!(__MODULE__, "CREATE SCHEMA IF NOT EXISTS #{@schema}", [])
    Ecto.Migrator.run(__MODULE__, path, :up, all: true, prefix: @schema)
  end
end
