defmodule RegentsWeb.Keyfleet.AgentTools.Keys do
  @moduledoc """
  Keys as an agent reads and keeps them: a Key as its page shows it
  (`show`), the Keys a wallet holds (`held`), taking a post off the wall of a Key it acts as (`wall_remove`),
  choosing the Key its person writes as (`post_as`), which of its person's
  agents is on which of their Keys (`agents`), its own mutes
  (`mutes`, `mute`, `unmute`) and its active shards (`shards`). Each takes
  what its signed request takes, checked as that request's body is, and answers and
  refuses as it does (`RegentsWeb.Keyfleet.AgentTools.Run`,
  `RegentsWeb.Keyfleet.AgentTools.Keys.Answer`). Only an agent runs them, never a
  connected app on its own; the Keys' own policies decide what it does.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run

  @fleet [max_length: 63, trim?: false]
  @key [match: ~r/\A[1-9][0-9]{0,17}\z/]

  actions do
    action :show, :map do
      description "A sold Key as its page shows it, and whether you act as it now."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: @key
      run {Run, tool: "keys_show"}
    end

    action :held, :map do
      description "The Keys a wallet holds in a fleet now, lowest first."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :wallet, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A0x[0-9a-fA-F]{40}\z/]

      run {Run, tool: "keys_held"}
    end

    action :wall_remove, :map do
      description "Takes a post off the wall of a Key you act as, for everyone."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: @key

      argument :message_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/]

      run {Run, tool: "walls_remove"}
    end

    action :post_as, :map do
      description "Chooses which of your person's Keys in a fleet they and their agents write as."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :token_id, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: 9_007_199_254_740_991]

      run {Run, tool: "keys_post_as"}
    end

    action :agents, :map do
      description "Your person's Keys in a fleet, the agents on each and their paired agents."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "keys_agents"}
    end

    action :mutes, :map do
      description "The Keys you have muted in a fleet."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "mutes_list"}
    end

    action :mute, :map do
      description "Mutes a sold Key for you in a fleet, leaving its posts out of your reads."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: [max_length: 18]
      run {Run, tool: "mutes_add"}
    end

    action :unmute, :map do
      description "Unmutes a Key in a fleet, so your reads show its posts again."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: [max_length: 18]
      run {Run, tool: "mutes_remove"}
    end

    action :shards, :map do
      description "The active shards your own wallet holds, each with how to end it."
      run {Run, tool: "shards_list"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
