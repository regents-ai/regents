defmodule Regents.Repo.Migrations.KeyfleetAshFunctionsV7Extensions1 do
  @moduledoc """
  Keyfleet's move of `ash_required` to version 7 of the Ash functions. On
  regents.sh that version is already in `public`, put there by regents.sh's own
  migrations, which run before any product's (`Regents.Products.migration_areas/0`),
  so this version changes nothing there. It is kept so Keyfleet's ledger holds
  the versions production's does.
  """

  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
