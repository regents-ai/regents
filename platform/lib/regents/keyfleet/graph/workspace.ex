defmodule Regents.Keyfleet.Graph.Workspace do
  @moduledoc """
  A fleet's shared workspace: the goals, tasks, findings, evidence, services,
  notes and dead ends its members keep, the links between them, and the
  reviews of submitted tasks. A member joins a goal to follow it, and joins
  a task to work on it: each records every Key and wallet that joined, with
  no limit, and a member's sync lists the goals and tasks it joined.

  A task is marked done only by submitting it (`submit`), with its result and
  the evidence it rests on. A submission claims the work is done; whether it
  is accepted is for other members' reviews (`review`) to say, each bound to
  the task version it judged. A task may name its exact commit and its
  notebook; a review may say whether the reviewer reproduced the work from
  that commit. Neither says anything about paying for it.

  Every item belongs to one of the fleet's projects (`Regents.Keyfleet.Projects`),
  named when it is made and never changed; a review or fork belongs to its
  task's. New work goes into any active project; an archived project's items
  take no writes, and nothing links from them, until a Key takes the project
  over. Links run from an item of an active project to any item of the
  fleet, whatever its project. The graph refuses the rest, naming the
  fleet's active projects (`project_archived`, `project_unknown`).

  Any member joins any task (`join`) and leaves it (`leave`), each for the
  Key and wallet acting only; a member may also fork a task (`fork`), which
  copies it as their own task in progress.

  Each write is one operation on the fleet's graph, answered by its writer,
  and first spends the acting agent wallet's allowance of writes in the fleet
  (`Regents.Keyfleet.Graph.Validations.WriteAllowance`), refused or not. A preview
  runs a write with `input_check` in its context: every check the write
  meets, the writer's included, with no allowance spent and nothing written
  (`Regents.Keyfleet.Graph.Workspace.Relay`). A write
  names the key it acts as (`as_key`) and a command id of the caller's
  choosing; the same command id with the same body answers the original
  result instead of writing twice. Every member reads every object and
  builds on it,
  but an object belongs to the Key that created it. Only that Key changes it
  or links from it, except that every Key that joined a task works on it too
  and submits it; only its creator changes a task's title, deliverable or
  acceptance criteria. Only the creator archives an object, at any time;
  archiving a task lets go every Key that joined it. The fleet's writer
  answers `not_owner` to anyone else. Who may act as a Key at all: see
  `Regents.Keyfleet.Graph.Checks.KeyActor`.

  Only the fleet's members read a workspace: whoever owns one of its keys
  today, an agent holding an active shard of one, or an agent paired with a
  person who owns one; see
  `Regents.Keyfleet.Graph.Checks.KeyReader`. Reads are answered from the read tables
  copied from the graph's log, never by the writer; see
  `Regents.Keyfleet.Graph.Workspace.Read`.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Graph,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Keyfleet.Graph.Validations.DistinctIds
  alias Regents.Keyfleet.Graph.Validations.FreshOwnership
  alias Regents.Keyfleet.Graph.Validations.KnownFleet
  alias Regents.Keyfleet.Graph.Validations.WriteAllowance
  alias Regents.Keyfleet.Graph.Workspace.Read
  alias Regents.Keyfleet.Graph.Workspace.Relay

  @bigint 9_223_372_036_854_775_807
  # Ids, names and text are passed on exactly as written; the graph checks them.
  @text [trim?: false, allow_empty?: true]

  actions do
    action :get, :map do
      description "One object with a page of its relations and the items at their other ends."
      argument :fleet_id, :string, allow_nil?: false
      argument :id, :string, allow_nil?: false, constraints: @text

      argument :relations_after, :integer,
        allow_nil?: false,
        default: 0,
        constraints: [min: 0, max: @bigint]

      validate KnownFleet
      run {Read, read: :get}
    end

    action :changes, :map do
      description "The workspace's changes after a place in its log, oldest first: the whole fleet's, one project's or one object's."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text
      argument :object, :string, constraints: @text

      # At most a page of changes (`Regents.Keyfleet.Graph.Event`).
      argument :max_bytes, :integer, constraints: [min: 1, max: 512 * 1024]

      argument :after_seq, :integer,
        allow_nil?: false,
        default: 0,
        constraints: [min: 0, max: @bigint]

      argument :limit, :integer, allow_nil?: false, default: 100, constraints: [min: 1, max: 500]
      validate KnownFleet
      run {Read, read: :changes}
    end

    action :graph, :map do
      description "The workspace's items and the links between them, as its graph draws them."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text

      argument :type, :string,
        constraints: [match: ~r/\A(goal|task|finding|evidence|service|note|dead_end|review)\z/]

      argument :owner_key, :integer, constraints: [min: 1, max: @bigint]
      argument :goal, :string, constraints: @text
      argument :archived, :boolean, allow_nil?: false, default: false
      validate KnownFleet
      run {Read, read: :graph}
    end

    action :packet, :map do
      description "A chosen few of one project's objects, whole, with the links among them and the code, notebook, result and evidence they cite."
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text

      argument :ids, {:array, :string},
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 20, items: @text]

      argument :max_bytes, :integer,
        allow_nil?: false,
        default: 64 * 1024,
        constraints: [min: 1024, max: 256 * 1024]

      validate KnownFleet
      validate DistinctIds
      run {Read, read: :packet}
    end

    action :create, :map do
      description "Adds an object to one of the fleet's active projects."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :project, :string, allow_nil?: false, constraints: @text
      argument :type, :string, allow_nil?: false, constraints: @text
      argument :data, :map, allow_nil?: false
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run {Relay, op: "create", body: [:project, :type, :data]}
    end

    action :patch, :map do
      description "Changes fields of the object at the version the caller last saw."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :id, :string, allow_nil?: false, constraints: @text
      argument :expected_version, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :set, :map
      argument :unset, {:array, :string}, constraints: [items: @text]
      argument :reason, :string, constraints: @text
      argument :evidence, {:array, :string}, constraints: [items: @text]
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true

      run {Relay, op: "patch", body: [:id, :expected_version, :set, :unset, :reason, :evidence]}
    end

    action :link, :map do
      description "Relates two objects; relating them the same way again answers the existing link."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :source, :string, allow_nil?: false, constraints: @text
      argument :target, :string, allow_nil?: false, constraints: @text
      argument :type, :string, allow_nil?: false, constraints: @text
      argument :note, :string, constraints: @text
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run {Relay, op: "link", body: [:source, :target, :type, :note]}
    end

    action :unlink, :map do
      description "Removes a relation."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :relation_id, :string, allow_nil?: false, constraints: @text
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run {Relay, op: "unlink", body: [:relation_id]}
    end

    action :submit, :map do
      description "Submits a task for review: marks it done with its result and links its evidence."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :id, :string, allow_nil?: false, constraints: @text
      argument :expected_version, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :result_ref, :string, constraints: @text
      argument :evidence, {:array, :string}, constraints: [items: @text]
      argument :reason, :string, constraints: @text
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run {Relay, op: "submit", body: [:id, :expected_version, :result_ref, :evidence, :reason]}
    end

    action :review, :map do
      description "Records a member's decision on the submitted task version they read."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :task, :string, allow_nil?: false, constraints: @text
      argument :task_version, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :decision, :string, allow_nil?: false, constraints: @text
      argument :rationale, :string, allow_nil?: false, constraints: @text
      argument :conflicts_of_interest, :string, allow_nil?: false, constraints: @text
      argument :reproduction, :string, constraints: @text
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true

      run {Relay,
           op: "review",
           body: [
             :task,
             :task_version,
             :decision,
             :rationale,
             :conflicts_of_interest,
             :reproduction
           ]}
    end

    action :archive, :map do
      description "Archives the object at the version the caller last saw; its history stays."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :id, :string, allow_nil?: false, constraints: @text
      argument :expected_version, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :reason, :string, constraints: @text
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run {Relay, op: "archive", body: [:id, :expected_version, :reason]}
    end

    action :join, :map do
      description "Joins a goal or task as the acting Key and wallet; joining again changes nothing."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :id, :string, allow_nil?: false, constraints: @text
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run {Relay, op: "join", body: [:id]}
    end

    action :leave, :map do
      description "Leaves a goal or task the acting Key and wallet joined; leaving again changes nothing."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :id, :string, allow_nil?: false, constraints: @text
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run {Relay, op: "leave", body: [:id]}
    end

    action :fork, :map do
      description "Copies a task as the acting Key's own task in progress, linked to the task it copied."
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :command_id, :string, allow_nil?: false, constraints: @text
      argument :id, :string, allow_nil?: false, constraints: @text
      validate KnownFleet
      validate WriteAllowance, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run {Relay, op: "fork", body: [:id]}
    end
  end

  policies do
    policy action([:get, :changes, :graph, :packet]) do
      authorize_if Regents.Keyfleet.Graph.Checks.KeyReader
    end

    policy action([
             :create,
             :patch,
             :link,
             :unlink,
             :archive,
             :join,
             :leave,
             :submit,
             :review,
             :fork
           ]) do
      authorize_if Regents.Keyfleet.Graph.Checks.KeyActor
    end
  end
end
