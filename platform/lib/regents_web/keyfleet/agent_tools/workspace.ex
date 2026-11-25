defmodule RegentsWeb.Keyfleet.AgentTools.Workspace do
  @moduledoc """
  A fleet's workspace as an agent reads it: one item as its page shows it
  (`show`), what the workspace's pages keep at hand (`board`), its items and
  links as the Graph view draws them (`view`), its changes after a place in
  its log (`changes`), a packet of chosen items read together (`packet`), its Atlas, the swarm's work in one window and a page
  of the things changed in it (`atlas`, `atlas_things`,
  `RegentsWeb.Keyfleet.AgentTools.Workspace.Atlas`), and pinning or unpinning a
  project's notebook or code on its board (`pin`, `unpin`). Each answers what
  its signed request answers (`RegentsWeb.Keyfleet.AgentGraphController`) and refuses
  as it does (`RegentsWeb.Keyfleet.WorkspaceRefusal`): a reader who is none of the
  fleet's members is told so, or that the fleet's Key ownership is being
  refreshed. A pin takes what its signed request takes, checked as that
  request's body is (`RegentsWeb.Keyfleet.AgentTools.Run`,
  `RegentsWeb.Keyfleet.AgentTools.Workspace.Answer`). Only an agent runs them, never
  a connected app on its own; the workspace's own policies decide every read
  (`Regents.Keyfleet.Graph.Checks.KeyReader`), and the Atlas's its own.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run
  alias RegentsWeb.Keyfleet.AgentTools.Workspace.{Atlas, Read}

  @bigint 9_223_372_036_854_775_807
  # Ids, names and text are passed on exactly as written; the graph checks them.
  @text [trim?: false, allow_empty?: true]
  @part "owner_key|relations|linked|url|discussion|commit|rerun_check|agents"

  actions do
    action :show, :map do
      description "One item as its page shows it, in one read: its links, its page's address, the posts its discussion names and, for a task, its commit and what a rerun still needs."
      argument :fleet_id, :string, allow_nil?: false
      argument :id, :string, allow_nil?: false, constraints: @text

      argument :relations_after, :integer,
        allow_nil?: false,
        default: 0,
        constraints: [min: 0, max: @bigint]

      # The parts besides the item to answer, comma separated; all of them
      # when left out.
      argument :fields, :string, constraints: [match: ~r/\A(?:#{@part})(?:,(?:#{@part}))*\z/]

      run {Read, read: :show}
    end

    action :board, :map do
      description "What the workspace's pages keep at hand, the whole fleet's or one project's: how many goals and tasks stand where, its newest goals and what its members pinned in its Docs and its Code."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text
      run {Read, read: :board}
    end

    action :view, :map do
      description "The workspace's items, the links between them and the Keys that own them, as its Graph view draws them, or one goal's map, each item with its page's address."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text

      argument :type, :string,
        constraints: [match: ~r/\A(goal|task|finding|evidence|service|note|dead_end|review)\z/]

      argument :owner_key, :integer, constraints: [min: 1, max: @bigint]
      argument :goal, :string, constraints: @text
      argument :archived, :boolean, allow_nil?: false, default: false
      run {Read, read: :view}
    end

    action :changes, :map do
      description "The workspace's changes after a place in its log, oldest first: the whole fleet's, one project's or one item's."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text
      argument :object, :string, constraints: @text
      argument :max_bytes, :integer, constraints: [min: 1, max: 512 * 1024]

      argument :after_seq, :integer,
        allow_nil?: false,
        default: 0,
        constraints: [min: 0, max: @bigint]

      argument :limit, :integer, allow_nil?: false, default: 100, constraints: [min: 1, max: 500]
      run {Read, read: :changes}
    end

    action :packet, :map do
      description "A chosen 1 to 20 of one project's items whole, with the links among them and the code, notebook, result and evidence addresses they store, from one read."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text

      argument :ids, {:array, :string},
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 20, items: @text]

      argument :max_bytes, :integer,
        allow_nil?: false,
        default: 64 * 1024,
        constraints: [min: 1024, max: 256 * 1024]

      validate Regents.Keyfleet.Graph.Validations.DistinctIds
      run {Read, read: :packet}
    end

    action :atlas, :map do
      description "The fleet's Atlas for one window: its changes, things changed and Keys at work, in all and by bucket, and its most active things."
      argument :fleet_id, :string, allow_nil?: false

      argument :window, :atom,
        allow_nil?: false,
        default: :week,
        constraints: [one_of: [:day, :week, :month, :year]]

      argument :at, :utc_datetime_usec
      argument :bucket, :atom, constraints: [one_of: [:hour, :day, :week, :month]]
      argument :source, :atom, constraints: [one_of: [:graph, :notebook]]
      argument :project, :string, constraints: @text
      argument :by, :atom, constraints: [one_of: [:project, :kind]]

      argument :most_active, :integer,
        allow_nil?: false,
        default: 5,
        constraints: [min: 0, max: 50]

      run fn input, context -> Atlas.swarm(input.arguments, Ash.Context.to_opts(context)) end
    end

    action :atlas_things, :map do
      description "A page of the things changed in one window of the fleet's Atlas, the one changed last first or the most active first."
      argument :fleet_id, :string, allow_nil?: false

      argument :window, :atom,
        allow_nil?: false,
        default: :day,
        constraints: [one_of: [:hour, :day, :week, :month, :year]]

      argument :at, :utc_datetime_usec

      argument :order, :atom,
        allow_nil?: false,
        default: :newest,
        constraints: [one_of: [:newest, :active]]

      argument :source, :atom, constraints: [one_of: [:graph, :notebook]]
      argument :project, :string, constraints: @text

      argument :kind, :string,
        constraints: [
          match: ~r/\A(goal|task|finding|evidence|service|note|dead_end|review|notebook)\z/
        ]

      argument :limit, :integer, allow_nil?: false, default: 20, constraints: [min: 1, max: 100]
      argument :after, :string, constraints: @text
      run fn input, context -> Atlas.things(input.arguments, Ash.Context.to_opts(context)) end
    end

    action :pin, :map do
      description "Pins a notebook or code file/folder on a project's board."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text
      argument :place, :string, allow_nil?: false, constraints: [match: ~r/\A(docs|code)\z/]
      argument :target, :string, allow_nil?: false, constraints: [max_length: 1024, trim?: false]
      run {Run, tool: "workspace_pin"}
    end

    action :unpin, :map do
      description "Removes a pin you placed on a project's board."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text
      argument :place, :string, allow_nil?: false, constraints: [match: ~r/\A(docs|code)\z/]
      argument :target, :string, allow_nil?: false, constraints: [max_length: 1024, trim?: false]
      run {Run, tool: "workspace_unpin"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
