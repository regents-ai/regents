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
      description "An open fleet's latest thirty workspace changes (Key, paired agent name if any, and project title; never item titles, notes, or wallet addresses), or only newer changes after a cursor."
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

    action :fleet_seasons, :map do
      description "A fleet's settled seasons, newest first, up to 20 per page."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :before, :string, constraints: [max_length: 512, trim?: false]
      run {Run, tool: "fleet_seasons"}
    end

    action :fleet_season, :map do
      description "Up to 100 locked picks of one settled season of a fleet, with open and close prices and result."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :number, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[1-9][0-9]{0,18}\z/, max_length: 19, trim?: false]

      argument :after, :string, constraints: [max_length: 512, trim?: false]
      run {Run, tool: "fleet_season"}
    end

    action :about, :map do
      description "Keyfleet's About page: title and Markdown."
      run {Run, tool: "about"}
    end

    action :docs, :map do
      description "Keyfleet's developer documentation: title and Markdown."
      run {Run, tool: "docs"}
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :agent)
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
