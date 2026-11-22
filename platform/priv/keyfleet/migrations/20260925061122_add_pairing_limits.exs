defmodule Regents.Repo.Migrations.KeyfleetAddPairingLimits do
  @moduledoc """
  Adds the owner's limits to each pairing: four sentences and when they were
  written, all there or all absent. Pairings made before have none. Generated
  with `mix ash.codegen`.
  """

  use Ecto.Migration

  def up do
    alter table(:key_pairings) do
      add(:limits_money, :text)
      add(:limits_information, :text)
      add(:limits_outside, :text)
      add(:limits_check_first, :text)
      add(:limits_written_at, :utc_datetime_usec)
    end

    create constraint(:key_pairings, :key_pairings_limits_whole,
             check: """
               num_nulls(limits_money, limits_information, limits_outside, limits_check_first, limits_written_at) IN (0, 5)
             """
           )
  end

  def down do
    drop_if_exists(constraint(:key_pairings, :key_pairings_limits_whole))

    alter table(:key_pairings) do
      remove(:limits_written_at)
      remove(:limits_check_first)
      remove(:limits_outside)
      remove(:limits_information)
      remove(:limits_money)
    end
  end
end
