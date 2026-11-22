defmodule Regents.Repo.Migrations.KeyfleetDropChainCursorRescanFrom do
  @moduledoc """
  Drops the chain cursor's `rescan_from` column and its rule. It held the
  block a fleet's reading was stopped at; the reader no longer stops a fleet,
  and nothing reads it. It changes no other column. Going down puts back an
  empty column and its rule, not what the column held.
  """

  use Ecto.Migration

  def up do
    drop_if_exists(constraint(:chain_cursors, :chain_cursors_nonnegative_rescan_from))

    alter table(:chain_cursors) do
      remove(:rescan_from)
    end
  end

  def down do
    alter table(:chain_cursors) do
      add(:rescan_from, :bigint)
    end

    create constraint(:chain_cursors, :chain_cursors_nonnegative_rescan_from,
             check: """
               rescan_from >= 0
             """
           )
  end
end
