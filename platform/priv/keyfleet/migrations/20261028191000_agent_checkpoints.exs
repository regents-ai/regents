defmodule Regents.Repo.Migrations.KeyfleetAgentCheckpoints do
  @moduledoc """
  Where each agent left off in each fleet (`Keyfleet.Agents.Checkpoint`). It
  starts empty.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create table(:agent_checkpoints, primary_key: false) do
      add(:wallet, :text, null: false, primary_key: true)
      add(:fleet_id, :text, null: false, primary_key: true)
      add(:revision, :bigint, null: false)
      add(:state, :map, null: false)

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create constraint(:agent_checkpoints, :agent_checkpoints_revision, check: "revision >= 1")
  end
end
