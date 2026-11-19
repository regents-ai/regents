defmodule RegentPoints.Service do
  @moduledoc false
  use Ash.Resource, domain: RegentPoints, authorizers: [Ash.Policy.Authorizer]

  actions do
    action :summary, :map do
      argument :source_app, :string
      argument :actor_kind, :string
      run RegentPoints.Summary
    end

    action :leaderboard, :map do
      run RegentPoints.Leaderboard
    end

    action :record_event, :map do
      argument :event, :map, allow_nil?: false
      # Only RegentPoints.StartAwards sets it: its offers wait behind live ones.
      argument :start_run, :boolean, allow_nil?: false, default: false
      run RegentPoints.Intake
    end

    action :process_event, :map do
      argument :event_id, :uuid, allow_nil?: false
      run RegentPoints.Award
    end

    action :reverse, :map do
      argument :entry_id, :uuid, allow_nil?: false
      argument :correction_key, :string, allow_nil?: false, constraints: [min_length: 1]
      argument :points_micro, :integer, allow_nil?: false, constraints: [min: 1]
      argument :reason, :string, allow_nil?: false, constraints: [min_length: 1]
      run RegentPoints.Reverse
    end
  end

  policies do
    policy action(:summary) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo_app: :regent_points}
    end

    # The board is read once for every reader by the site, which hands each reader
    # only the rows and their own place (RegentPoints.Leaderboard).
    policy action([:leaderboard, :record_event, :process_event, :reverse]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end
