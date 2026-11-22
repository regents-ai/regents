defmodule Regents.Repo.Migrations.AutolaunchStockSearchExtensions1 do
  @moduledoc """
  Autolaunch's install of pg_trgm, the extension its search scores matches with
  (`word_similarity`). On regents.sh it is already in `public`, put there by
  regents.sh's own migrations, which run before any product's
  (`Regents.Products.migration_areas/0`), and Autolaunch's queries reach it there.
  So this version installs nothing and its rollback removes nothing (it removed
  nothing before either). It is kept so Autolaunch's ledger holds the versions
  production's does.
  """

  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
