defmodule RegentAgents.Migrations.AgentPictures do
  use Ecto.Migration

  def change do
    create table(:agent_pictures, prefix: "regent_agents", primary_key: false) do
      add(
        :paired_agent_id,
        references(:paired_agents, type: :uuid, prefix: "regent_agents", on_delete: :delete_all),
        primary_key: true
      )

      add(:bytes, :binary, null: false)
      add(:updated_at, :utc_datetime_usec, null: false)
    end

    create constraint(:agent_pictures, :agent_pictures_bytes_size,
             check: "octet_length(bytes) <= 65536",
             prefix: "regent_agents"
           )
  end
end
