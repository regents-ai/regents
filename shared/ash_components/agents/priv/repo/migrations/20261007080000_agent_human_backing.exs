defmodule RegentAgents.Migrations.AgentHumanBacking do
  @moduledoc """
  Each paired agent keeps the World ID person the SIWA service last named behind
  it, and how many agents that person stands behind, as of its latest verified
  request (Sean "139. a", 2026-10-07). Both are empty when no verified person
  stands behind it. The person's number groups their agents and is never shown.
  """

  use Ecto.Migration

  def change do
    alter table(:paired_agents, prefix: "regent_agents") do
      add(:human_id, :text)
      add(:same_person_agent_count, :integer)
    end

    create constraint(:paired_agents, :paired_agents_human_backing_complete,
             prefix: "regent_agents",
             check:
               "(human_id IS NULL AND same_person_agent_count IS NULL) OR " <>
                 "(human_id IS NOT NULL AND same_person_agent_count IS NOT NULL AND " <>
                 "same_person_agent_count >= 1)"
           )

    create index(:paired_agents, [:human_id],
             prefix: "regent_agents",
             name: :paired_agents_human_index,
             where: "human_id IS NOT NULL"
           )
  end
end
