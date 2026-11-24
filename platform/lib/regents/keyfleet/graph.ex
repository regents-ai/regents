defmodule Regents.Keyfleet.Graph do
  @moduledoc """
  Each fleet's shared workspace, kept in the fleet's own graph.

  Every call names its fleet. Writes go to the fleet's graph; a write names the
  key it acts as, `as_key`, and its own command id; see
  `Regents.Keyfleet.Graph.Workspace`. Reads are for the fleet's members
  (`Regents.Keyfleet.Graph.Checks.KeyReader`), except what a fleet shows anyone
  (`shown/1`), and are
  answered from read tables the projector keeps copied from the graph's log,
  so a read never waits on a write. Each read says how far along the log it reflects, its
  `watermark`.
  """
  use Ash.Domain

  @goals_shown 50
  @tables [
    Regents.Keyfleet.Graph.Cursor,
    Regents.Keyfleet.Graph.Event,
    Regents.Keyfleet.Graph.Object,
    Regents.Keyfleet.Graph.Relation
  ]

  resources do
    resource Regents.Keyfleet.Graph.Workspace do
      define :get_object, action: :get, args: [:fleet_id, :id]
      define :list_changes, action: :changes, args: [:fleet_id]
      define :workspace_graph, action: :graph, args: [:fleet_id]
      define :workspace_packet, action: :packet, args: [:fleet_id]
      define :create_object, action: :create, args: [:fleet_id]
      define :patch_object, action: :patch, args: [:fleet_id]
      define :link_objects, action: :link, args: [:fleet_id]
      define :unlink_relation, action: :unlink, args: [:fleet_id]
      define :archive_object, action: :archive, args: [:fleet_id]
      define :join, action: :join, args: [:fleet_id]
      define :leave, action: :leave, args: [:fleet_id]
      define :submit_task, action: :submit, args: [:fleet_id]
      define :review_task, action: :review, args: [:fleet_id]
      define :fork_task, action: :fork, args: [:fleet_id]
    end

    resource Regents.Keyfleet.Graph.Cursor do
      define :get_cursor, action: :read, get_by: [:fleet_id], not_found_error?: false
      define :uncounted_cursors, action: :uncounted
      define :mark_counted, action: :counted
      define :hold_cursor, action: :hold, args: [:fleet_id], not_found_error?: false
      define :start_cursor, action: :start
      define :advance_cursor, action: :advance
      define :forget_cursor, action: :forget
    end

    resource Regents.Keyfleet.Graph.Event do
      define :read_events, action: :page, args: [:fleet_id, :after_seq, :limit]
      define :latest_activity, action: :activity, args: [:fleet_id]
      define :notable_before, action: :notable_before, args: [:fleet_id, :before_seq, :limit]
      define :notable_after, action: :notable_after, args: [:fleet_id, :after_seq, :limit]
      define :object_history, action: :history, args: [:fleet_id, :object_id]

      define :object_events,
        action: :about_object,
        args: [:fleet_id, :object_id, :after_seq, :limit]

      define :record_events, action: :record
      define :events_with_ids, action: :with_event_ids, args: [:fleet_id, :event_ids]
      define :command_records, action: :command, args: [:fleet_id, :command_id]
      define :changes_after, action: :changes_after, args: [:fleet_id, :after_seq]
    end

    resource Regents.Keyfleet.Graph.Object do
      define :read_object, action: :in_fleet, args: [:fleet_id, :id], not_found_error?: false
      define :read_objects, action: :with_ids, args: [:fleet_id, :ids]
      define :workspace_cards, action: :cards, args: [:fleet_id]
      define :graph_objects, action: :graph, args: [:fleet_id]
      define :goal_work, action: :around_goal, args: [:fleet_id, :goal_id]
      define :object_titles, action: :titled, args: [:fleet_id, :ids]
      define :selected_objects, action: :selected, args: [:fleet_id, :project, :ids]
      define :search_objects, action: :search, args: [:fleet_id, :query]
      define :open_goals, action: :open_goals, args: [:fleet_id]

      define :shown_goal_tasks,
        action: :shown_goal_tasks,
        args: [:fleet_id, :project, :goals, :per_goal]

      define :work_citing, action: :citing, args: [:fleet_id, :uri]
      define :work_citing_any, action: :citing_any, args: [:fleet_id, :uris]
      define :tasks_naming_notebooks, action: :naming_notebooks, args: [:fleet_id, :uris]
      define :tasks_joined_by, action: :tasks_joined_by, args: [:fleet_id, :token_id, :wallet]
      define :awaiting_review, action: :awaiting_review, args: [:fleet_id]

      define :review_queue,
        action: :review_queue,
        args: [:fleet_id, :token_id, :ownership_epoch, :wallet]

      define :goals_joined_by, action: :joined_by, args: [:fleet_id, :token_id, :wallet]
      define :project_objects, action: :project
    end

    resource Regents.Keyfleet.Graph.Relation do
      define :read_relations_touching,
        action: :touching,
        args: [:fleet_id, :object_id, :after_seq, :limit]

      define :object_links, action: :linked, args: [:fleet_id, :object_id]
      define :producers_of, action: :producing, args: [:fleet_id, :targets]
      define :relations_among, action: :among, args: [:fleet_id, :ids]
      define :project_relations, action: :project
      define :remove_relations, action: :remove
      define :read_relations, action: :with_ids, args: [:fleet_id, :ids]
    end

    resource Regents.Keyfleet.Graph.Pin do
      define :pin, action: :pin
      define :unpin, action: :destroy
      define :pins, action: :in_place, args: [:fleet_id, :place, {:optional, :project}]
    end
  end

  @doc """
  What a fleet shows anyone of its workspace, read from one snapshot
  (`in_snapshot/1`): each of its projects by title, oldest first, with the
  titles of the open goals in it (the `:open_goals` read of objects),
  most recently changed first, up to #{@goals_shown} across the fleet. A
  project with no open goal is listed with none. Nothing else of the
  workspace is shown: not a project's name, a goal's other fields, a task, a
  count or a change.

  Never call it inside a transaction: its snapshot has to be its
  transaction's first statement. Inside an ordinary transaction that fails
  loudly; inside a repeatable-read one it doesn't fail, but reads that
  transaction's snapshot, taken at its first query, rather than one of its
  own.
  """
  @spec shown(String.t()) :: [%{name: String.t(), title: String.t(), goals: [String.t()]}]
  def shown(fleet_id) do
    {:ok, shown} =
      in_snapshot(fn ->
        goals =
          fleet_id
          |> open_goals!(query: [limit: @goals_shown])
          |> Enum.group_by(& &1.project, & &1.title)

        for project <- Regents.Keyfleet.Projects.project_titles!(fleet_id),
            do: %{
              name: project.name,
              title: project.title,
              goals: Map.get(goals, project.name, [])
            }
      end)

    shown
  end

  @doc """
  How many of a fleet's goals and tasks stand where, or one project's,
  archived ones left out, counted in one query of the `:tallied` read of
  objects: its open goals (a starting goal once someone joined it), and its
  tasks by the standing the Graph colours them by: not started
  (`open_tasks`), in progress (`working`), submitted and waiting for a
  review (`waiting_review`), blocked or disputed (`blocked`), and accepted,
  reproduced or not (`accepted`). Each task stands in one of them. Only the
  fleet's members read it.
  """
  @spec tally(String.t(), String.t() | nil, keyword()) ::
          {:ok, %{atom() => non_neg_integer()}} | {:error, term()}
  def tally(fleet_id, project, opts) do
    require Ash.Expr

    Regents.Keyfleet.Graph.Object
    |> Ash.Query.for_read(:tallied, %{fleet_id: fleet_id, project: project}, opts)
    |> Ash.aggregate(
      [
        {:open_goals, :count,
         query: [
           filter:
             Ash.Expr.expr(
               type == "goal" and fragment("(? ->> 'status') = 'open'", data) and
                 fragment(
                   "(? ->> 'starting' IS NULL OR jsonb_array_length(? -> 'joined') > 0)",
                   sys,
                   sys
                 )
             )
         ]},
        {:open_tasks, :count,
         query: [
           filter: Ash.Expr.expr(type == "task" and fragment("(? ->> 'progress') = 'todo'", data))
         ]},
        {:working, :count,
         query: [
           filter:
             Ash.Expr.expr(type == "task" and fragment("(? ->> 'progress') = 'doing'", data))
         ]},
        {:waiting_review, :count,
         query: [filter: Ash.Expr.expr(type == "task" and review == "awaiting_review")]},
        {:blocked, :count,
         query: [
           filter:
             Ash.Expr.expr(
               type == "task" and
                 (fragment("(? ->> 'progress') = 'blocked'", data) or review == "disputed")
             )
         ]},
        {:accepted, :count,
         query: [filter: Ash.Expr.expr(type == "task" and review in ["accepted", "reproduced"])]}
      ],
      opts
    )
  end

  @doc "`tally/3`, raising what it can't count."
  def tally!(fleet_id, project, opts) do
    case tally(fleet_id, project, opts) do
      {:ok, counts} -> counts
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  @doc """
  How large the fleet's workspace record stood at `before`, counted in one
  query of the events its log had taken by then (the `:taken_before` read of
  events): `bytes`, those events as a reader receives them, and `items`, the
  items made by then. The changes of a deleted project are no longer in the
  record, so they are not counted. Only the server counts it.
  """
  @spec record_size(String.t(), DateTime.t()) :: %{
          bytes: non_neg_integer(),
          items: non_neg_integer()
        }
  def record_size(fleet_id, before) do
    require Ash.Expr

    system = [actor: %Regents.Account.Actors.System{}]

    Regents.Keyfleet.Graph.Event
    |> Ash.Query.for_read(:taken_before, %{fleet_id: fleet_id, before: before}, system)
    |> Ash.aggregate!(
      [
        {:bytes, :sum, field: :byte_size, default: 0},
        {:items, :count, query: [filter: Ash.Expr.expr(type == "object.created")]}
      ],
      system
    )
  end

  @doc """
  Runs `read` in one read-only snapshot of the workspace's read tables and
  answers `{:ok, result}`: Postgres fixes a repeatable-read snapshot at the
  transaction's first query, so everything `read` reads comes from one
  moment. Never call it inside a transaction: the setting has to be the
  transaction's first statement. Inside an ordinary transaction that fails
  loudly; inside a repeatable-read one it doesn't fail, but `read` sees that
  transaction's snapshot, taken at its first query, rather than one of its
  own. The read-only setting ends with `read`: the outer transaction can
  write again once it returns.
  """
  def in_snapshot(read) do
    Ash.transact(@tables, fn ->
      Regents.Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
      read.()
    end)
  end

  @doc """
  Where a fleet tells its members how far its workspace's read tables have
  reached, as `{:graph_head, fleet_id, run_id, watermark}`: the log they copy
  and the place in it. A notice is only a hint to read again; a reader that
  misses one loses nothing, because it reads on from its own cursor.
  """
  def head_topic(fleet_id), do: "keyfleet:fleet:#{fleet_id}:graph"

  @doc """
  Where a fleet tells anyone that its activity has a new workspace change to
  show them (`notable_before/3`), as `{:graph_notable, fleet_id}`. It says
  nothing of any other change, nor how far the log has got.
  """
  def notable_topic(fleet_id), do: "keyfleet:fleet:#{fleet_id}:graph:notable"

  @doc """
  Where a reader of `class` (`Regents.Keyfleet.Access.class/2`) hears of the fleet's
  workspace: `head_topic/1` for whoever reads the workspace, `notable_topic/1`
  for anyone else. A listener is on one of the two, never both.
  """
  def topic(fleet_id, class) do
    if Regents.Keyfleet.Access.enough?(class, :read, :workspace),
      do: head_topic(fleet_id),
      else: notable_topic(fleet_id)
  end
end
