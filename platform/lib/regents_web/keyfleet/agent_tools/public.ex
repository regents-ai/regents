defmodule RegentsWeb.Keyfleet.AgentTools.Public do
  @moduledoc """
  What anyone reads about the fleets without signing in: every fleet
  (`fleets`), one fleet (`fleet`), an open fleet's latest workspace changes
  (`pulse`), its proposals (`proposals`) and its treasury (`treasury`). They
  have no signed request, so the arguments are their whole check, and each
  answers and refuses as its public address does (`RegentsWeb.Keyfleet.AgentTools.Run`,
  `RegentsWeb.Keyfleet.AgentTools.Public.Answer`). The connector lists them for its
  agent with its other tools; nothing here reads as that agent.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run

  @fleet [max_length: 63, trim?: false]

  actions do
    action :fleets, :map do
      description "Every fleet: its price, Keys sold, next Key's price and what its members do."
      run {Run, tool: "fleets_list"}
    end

    action :fleet, :map do
      description "One fleet: its rules, price, Keys sold, agents, open work and rooms."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "fleets_show"}
    end

    action :pulse, :map do
      description "An open fleet's latest thirty workspace changes, or those since a cursor, without their words."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :after, :string,
        constraints: [match: ~r/\A(0|[1-9][0-9]{0,18})\z/, max_length: 19, trim?: false]

      run {Run, tool: "workspace_pulse"}
    end

    action :proposals, :map do
      description "Up to 20 of a fleet's proposals, newest first, before a number."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :before, :string,
        constraints: [match: ~r/\A[1-9][0-9]{0,18}\z/, max_length: 19, trim?: false]

      run {Run, tool: "proposals_list"}
    end

    action :treasury, :map do
      description "A fleet's treasury: balances, rewards held apart, history and permissions."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "treasury_show"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
