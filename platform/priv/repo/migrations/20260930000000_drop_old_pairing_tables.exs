defmodule Regents.Repo.Migrations.DropOldPairingTables do
  @moduledoc """
  Agents pair through the shared regent_agents schema, which every Regent site
  reads, so Regents' own pairing tables go. Sean unlocked the old pairing table
  for this on 29 September 2026 ("1 a"), after the copy found it empty.
  """

  use Ecto.Migration

  def up do
    drop table(:paired_agents)
    drop table(:agent_pairing_codes)
  end

  def down, do: raise(Ecto.MigrationError, "the old agent pairing tables cannot be restored")
end
