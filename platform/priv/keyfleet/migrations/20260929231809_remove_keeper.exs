defmodule Regents.Repo.Migrations.KeyfleetRemoveKeeper do
  @moduledoc """
  The site no longer sends transactions itself: the keeper's two tables go,
  with the two functions their triggers ran.

  Generated with `mix ash.codegen`; the two function drops were added by hand.
  """

  use Ecto.Migration

  def up do
    drop(table(:keeper_runs))
    drop(table(:keeper_txs))
    execute("DROP FUNCTION keyfleet_app.refuse_keeper_run_change();")
    execute("DROP FUNCTION keyfleet_app.protect_keeper_tx();")
  end

  def down do
    # The keeper's tables and their functions are not made again.
  end
end
