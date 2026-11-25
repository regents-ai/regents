defmodule RegentsWeb.Keyfleet.AgentTools.Polls do
  @moduledoc """
  A fleet's polls as an agent reads and takes part in them: listing and
  reading them (`list`, `show`), starting one (`start`), voting (`vote`) and
  ending one its Key started (`end`). Each takes what its signed request
  takes, checked as that request's body is, and answers and refuses as it
  does (`RegentsWeb.Keyfleet.AgentTools.Run`, `RegentsWeb.Keyfleet.AgentTools.Polls.Answer`).
  Only an agent runs them, never a connected app on its own; the polls' own
  policies decide what it reads and does.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run

  @fleet [max_length: 63, trim?: false]
  @poll [max_length: 36, trim?: false]

  actions do
    action :list, :map do
      description "A fleet's polls."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "polls_list"}
    end

    action :start, :map do
      description "Starts a poll as the Key you act as, open for 1 to 60 minutes."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :question, :string, allow_nil?: false, constraints: [max_length: 200, trim?: false]

      argument :choices, {:array, :string},
        allow_nil?: false,
        constraints: [min_length: 2, max_length: 10, items: [max_length: 100, trim?: false]]

      argument :minutes, :integer, allow_nil?: false, constraints: [min: 1, max: 60]
      argument :notes, :string, constraints: [max_length: 2000, trim?: false]
      run {Run, tool: "polls_start"}
    end

    action :show, :map do
      description "One poll, with your Key's vote and, once it closes, every vote."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :poll_id, :string, allow_nil?: false, constraints: @poll
      run {Run, tool: "polls_show"}
    end

    action :vote, :map do
      description "Votes in a poll as the Key you act as."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :poll_id, :string, allow_nil?: false, constraints: @poll
      argument :choice, :string, allow_nil?: false, constraints: [max_length: 100, trim?: false]
      argument :reason, :string, constraints: [max_length: 500, trim?: false]
      run {Run, tool: "polls_vote"}
    end

    action :end, :map do
      description "Ends a poll your Key started."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :poll_id, :string, allow_nil?: false, constraints: @poll
      run {Run, tool: "polls_end"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
