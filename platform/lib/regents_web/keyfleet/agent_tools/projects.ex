defmodule RegentsWeb.Keyfleet.AgentTools.Projects do
  @moduledoc """
  A fleet's projects as an agent reads and keeps them: listing them (`list`)
  and, as a Key, starting, archiving, taking over and deleting one (`start`,
  `archive`, `take_over`, `delete`), and giving one it holds its one-line
  description and choosing whether its page shows its work to everyone
  (`describe`, `show`). Each takes what its signed request takes, checked as
  that request's body is, and answers and refuses as it does
  (`RegentsWeb.Keyfleet.AgentTools.Run`, `RegentsWeb.Keyfleet.AgentTools.Projects.Answer`).
  Only an agent runs them, never a connected app on its own; the projects'
  own policies decide what it may do.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run

  @fleet [max_length: 63, trim?: false]
  @key [min: 1]

  actions do
    action :list, :map do
      description "A fleet's projects, active ones first, and the one your Key works on."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "projects_list"}
    end

    action :start, :map do
      description "Starts a project held by the Key you act as."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :as_key, :integer, allow_nil?: false, constraints: @key

      argument :name, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/, max_length: 32]

      argument :title, :string, allow_nil?: false, constraints: [max_length: 60, trim?: false]
      run {Run, tool: "projects_start"}
    end

    action :archive, :map do
      description "Archives the project the Key you act as holds."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :as_key, :integer, allow_nil?: false, constraints: @key
      run {Run, tool: "projects_archive"}
    end

    action :take_over, :map do
      description "Takes over an archived project as the Key you act as."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :project, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/, max_length: 32]

      argument :as_key, :integer, allow_nil?: false, constraints: @key
      run {Run, tool: "projects_take_over"}
    end

    action :delete, :map do
      description "Deletes an archived project the Key you act as started."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :project, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/, max_length: 32]

      argument :as_key, :integer, allow_nil?: false, constraints: @key
      run {Run, tool: "projects_delete"}
    end

    action :describe, :map do
      description "Sets a held project's one-line description; an empty line takes it away."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :project, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/, max_length: 32]

      argument :as_key, :integer, allow_nil?: false, constraints: @key

      argument :description, :string,
        allow_nil?: false,
        constraints: [allow_empty?: true, trim?: false]

      run {Run, tool: "projects_describe"}
    end

    action :show, :map do
      description "Chooses whether a project's page shows its work to everyone."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :project, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/, max_length: 32]

      argument :as_key, :integer, allow_nil?: false, constraints: @key
      argument :shown_to_everyone, :boolean, allow_nil?: false
      run {Run, tool: "projects_show"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
