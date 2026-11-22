defmodule Regents.Repo.Migrations.KeyfleetAgentKeys do
  @moduledoc """
  Which of a person's Keys in a fleet each of their paired agents is on, and
  the Key's ownership record when it was put there (`Keyfleet.Keys.AgentKey`):
  one row per agent per fleet, any number per Key. A new, empty table;
  nothing that exists changes.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create table(:agent_keys, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:human_account_id, :bigint, null: false)
      add(:token_id, :bigint, null: false)
      add(:paired_agent_id, :uuid, null: false)
      add(:ownership_epoch, :bigint, null: false)

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :fleet_id,
        references(:fleets,
          column: :id,
          name: "agent_keys_fleet_id_fkey",
          type: :text,
          prefix: "keyfleet_app"
        ), null: false)
    end

    create unique_index(:agent_keys, [:paired_agent_id, :fleet_id],
             name: "agent_keys_one_key_per_agent_index"
           )

    create index(:agent_keys, [:human_account_id, :fleet_id], name: "agent_keys_person_index")

    create constraint(:agent_keys, :agent_keys_positive_token,
             check: """
               token_id > 0
             """
           )

    create constraint(:agent_keys, :agent_keys_positive_epoch,
             check: """
               ownership_epoch >= 1
             """
           )
  end

  def down do
    drop(table(:agent_keys))
  end
end
