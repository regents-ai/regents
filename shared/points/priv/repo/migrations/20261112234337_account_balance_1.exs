defmodule RegentPoints.Repo.Migrations.AccountBalance1 do
  @moduledoc """
  The board's index on the stored totals, highest first and then the lowest
  account id, built without blocking writes.

  Generated with Ash; the column list is written as `{:desc, :balance_micro}`
  because the generated keyword form does not compile, and the way back drops the
  index concurrently too.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:accounts, [{:desc, :balance_micro}, :id],
             concurrently: true,
             prefix: "regent_points"
           )
  end

  def down do
    drop_if_exists(
      index(:accounts, [{:desc, :balance_micro}, :id],
        concurrently: true,
        prefix: "regent_points"
      )
    )
  end
end
