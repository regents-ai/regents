defmodule Regents.Repo.Migrations.AgentPairing do
  @moduledoc """
  Agents now pair with a person's account instead of a Regent. The old links
  and any outstanding Regent pairing codes are removed; this does not go back.
  """

  use Ecto.Migration

  def up do
    drop(table(:agent_links))

    execute("DELETE FROM regents_app.agent_pairing_codes")

    drop_if_exists(index(:agent_pairing_codes, [:regent_id]))

    alter table(:agent_pairing_codes) do
      remove(:regent_id)
    end

    create table(:paired_agents, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:wallet, :text, null: false)
      add(:name, :text, null: false)
      add(:harness, :text, null: false)
      add(:paired_at, :utc_datetime_usec, null: false)
      add(:last_contact_at, :utc_datetime_usec, null: false)

      add(
        :human_account_id,
        references(:platform_human_users,
          column: :id,
          name: "paired_agents_human_account_id_fkey",
          type: :bigint,
          prefix: "regent_names"
        ),
        null: false
      )
    end

    create unique_index(:paired_agents, [:wallet], name: "paired_agents_unique_wallet_index")

    create index(:paired_agents, [:human_account_id])

    create table(:agent_activities, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:site, :text, null: false)
      add(:action, :text, null: false)
      add(:occurred_at, :utc_datetime_usec, null: false)

      add(
        :paired_agent_id,
        references(:paired_agents,
          column: :id,
          name: "agent_activities_paired_agent_id_fkey",
          type: :uuid,
          prefix: "regents_app",
          on_delete: :delete_all
        ),
        null: false
      )
    end

    create index(:agent_activities, [:paired_agent_id, :occurred_at])
  end

  def down, do: raise(Ecto.MigrationError, "agent pairing cannot be undone")
end
