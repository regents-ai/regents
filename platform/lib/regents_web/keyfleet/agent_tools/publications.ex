defmodule RegentsWeb.Keyfleet.AgentTools.Publications do
  @moduledoc """
  What the fleet's Keys made public in a project, as an agent reads and
  makes it: listing it (`list`), making a Key's posts, an item it added, a
  saved notebook page or a commit public (`posts`, `item`, `page`,
  `commit`), and taking something back (`withdraw`). Each takes what its
  signed request takes, checked as that request's body is, and answers and
  refuses as it does (`RegentsWeb.Keyfleet.AgentTools.Run`,
  `RegentsWeb.Keyfleet.AgentTools.Publications.Answer`). Only an agent runs them,
  never a connected app on its own; the projects' own policies decide what
  it makes public.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run

  @fleet [max_length: 63, trim?: false]
  @project [match: ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/, max_length: 32]
  @commit [match: ~r/\A([0-9a-f]{40}|[0-9a-f]{64})\z/]

  actions do
    action :list, :map do
      description "What is public in a project, newest first, 100 at a time."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :project, :string, allow_nil?: false, constraints: @project
      argument :after, :string, constraints: [trim?: false]
      run {Run, tool: "publications_list"}
    end

    action :posts, :map do
      description "Makes your Key's posts in a room public, from one post to another."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :project, :string, allow_nil?: false, constraints: @project
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1]
      argument :room, :string, allow_nil?: false, constraints: [max_length: 63, trim?: false]
      argument :from_seq, :integer, allow_nil?: false, constraints: [min: 1]
      argument :to_seq, :integer, allow_nil?: false, constraints: [min: 1]
      run {Run, tool: "publications_posts"}
    end

    action :item, :map do
      description "Makes a workspace item your Key added public."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1]
      argument :item, :string, allow_nil?: false, constraints: [max_length: 128, trim?: false]
      run {Run, tool: "publications_item"}
    end

    action :page, :map do
      description "Makes a saved notebook page you made public."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1]
      argument :page, :string, allow_nil?: false, constraints: [max_length: 512, trim?: false]
      run {Run, tool: "publications_page"}
    end

    action :commit, :map do
      description "Makes the code at one commit of your Key's project public."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :project, :string, allow_nil?: false, constraints: @project
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1]
      argument :commit, :string, allow_nil?: false, constraints: @commit
      run {Run, tool: "publications_commit"}
    end

    action :withdraw, :map do
      description "Takes back something your Key made public."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :publication_id, :uuid, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1]
      run {Run, tool: "publications_withdraw"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
