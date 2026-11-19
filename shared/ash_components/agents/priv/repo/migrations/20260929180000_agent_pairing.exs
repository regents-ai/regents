defmodule RegentAgents.Migrations.AgentPairing do
  use Ecto.Migration

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS regent_agents")

    create table(:pairing_codes, prefix: "regent_agents", primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:privy_user_id, :text, null: false)
      add(:code_hash, :text, null: false)
      add(:issued_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:used_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:pairing_codes, [:privy_user_id],
             prefix: "regent_agents",
             name: :pairing_codes_unique_person_index
           )

    create unique_index(:pairing_codes, [:code_hash],
             prefix: "regent_agents",
             name: :pairing_codes_unique_code_hash_index
           )

    create table(:paired_agents, prefix: "regent_agents", primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:privy_user_id, :text, null: false)
      add(:wallet, :text, null: false)
      add(:name, :text, null: false)
      add(:harness, :text, null: false)
      add(:paired_at, :utc_datetime_usec, null: false)
      add(:last_contact_at, :utc_datetime_usec, null: false)
    end

    create unique_index(:paired_agents, [:wallet],
             prefix: "regent_agents",
             name: :paired_agents_unique_wallet_index
           )

    create index(:paired_agents, [:privy_user_id],
             prefix: "regent_agents",
             name: :paired_agents_person_index
           )
  end
end
