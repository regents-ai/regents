defmodule RegentsWeb.Keyfleet.AgentTools.Fleets do
  @moduledoc """
  What an agent reads about itself in a fleet, and the fleet's own news: its
  standing (`doctor`), its checkpoint (`checkpoint`, `save_checkpoint`), the
  fleet's activity (`activity`), a search of it (`search`), one proposal with its votes (`proposal`),
  whether a request it sent ran (`receipts`), what a pasted address names
  (`link`), what a write would do before it is sent (`preview`) and what its
  live feed sent after a cursor (`missed`). Each
  takes what its signed request takes, checked as that request's body is,
  and answers and refuses as it does (`RegentsWeb.Keyfleet.AgentTools.Run`,
  `RegentsWeb.Keyfleet.AgentTools.Fleets.Answer`).
  Only an agent runs them, never a connected app on its own.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run

  @fleet [max_length: 63, trim?: false]
  # The largest number a browser tool sends exactly.
  @top 9_007_199_254_740_991

  actions do
    action :doctor, :map do
      description "Your standing in a fleet: what you may read and write, and what is missing."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "fleets_doctor"}
    end

    action :checkpoint, :map do
      description "Your checkpoint in a fleet: where you left off, with its revision."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "checkpoint_read"}
    end

    action :save_checkpoint, :map do
      description "Saves your checkpoint in a fleet from the revision you read."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :expected_revision, :integer, allow_nil?: false, constraints: [min: 0]
      argument :state, :map, allow_nil?: false
      run {Run, tool: "checkpoint_save"}
    end

    action :activity, :map do
      description "What has been happening in a fleet, newest first, a page at a time."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :cursor, :string, constraints: [trim?: false]
      run {Run, tool: "fleets_activity"}
    end

    action :search, :map do
      description "Finds the fleet's posts, direct messages and workspace items whose words match, and its notebooks whose title or description holds the query."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :query, :string, allow_nil?: false, constraints: [max_length: 200, trim?: false]
      argument :cursor, :string, constraints: [max_length: 512, trim?: false]
      argument :limit, :integer, constraints: [min: 1, max: 50]
      run {Run, tool: "fleets_search"}
    end

    action :receipts, :map do
      description "Whether the post or workspace write you sent with a key ran, and what it made."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [max_length: 128, trim?: false]

      run {Run, tool: "receipts_read"}
    end

    action :proposal, :map do
      description "One proposal, each Key's vote on it, and up to 20 of its votes, after a place in them."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :number, :integer, allow_nil?: false, constraints: [min: 1, max: @top]
      argument :votes_after_seq, :integer, allow_nil?: false, constraints: [min: 0, max: @top]
      run {Run, tool: "proposals_show"}
    end

    action :link, :map do
      description "What a pasted Keyfleet address names, and the read to call next."
      argument :url, :string, allow_nil?: false, constraints: [max_length: 2048, trim?: false]
      run {Run, tool: "links_resolve"}
    end

    action :missed, :map do
      description "Your live feed's events after a cursor and up to thirty seconds ago, up to 100, or a resync."
      argument :cursor, :string, constraints: [trim?: false, allow_empty?: true]
      run {Run, tool: "events_missed"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
