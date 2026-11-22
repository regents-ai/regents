defmodule Regents.Repo.Migrations.AutolaunchInitializeExtensions1 do
  @moduledoc """
  Autolaunch's first install of the Ash functions (`ash_elixir_or`, `ash_elixir_and`,
  `ash_trim_whitespace`, `ash_raise_error`, `ash_required`, `uuid_generate_v7`).
  On regents.sh they are already in `public`, put there by regents.sh's own
  migrations, which run before any product's (`Regents.Products.migration_areas/0`),
  so this version installs nothing and its rollback removes nothing. It is kept so
  Autolaunch's ledger holds the versions production's does.
  """

  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
