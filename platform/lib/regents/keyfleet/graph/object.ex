defmodule Regents.Keyfleet.Graph.Object do
  @moduledoc """
  One workspace object as the fleet's graph log last left it: its member
  fields (`data`), its server-owned fields (`sys`), its version and the
  project it belongs to (`Regents.Keyfleet.Projects`), copied from `sys` so a project's
  objects are read by index.

  A task marked done has been submitted for review, and its `review` says
  where that stands: `awaiting_review` until a review of the task's current
  version has been recorded, then `disputed` if any review of that version
  disputes it, `reproduced` if one accepting it says the reviewer ran the
  work again from its commit and it reproduced, otherwise `accepted`. Any
  change to the task makes a new version, which waits for review again. A
  task not submitted has no `review`, whatever its author says it ran: its
  `progress` is all Keyfleet knows of it.

  An object last changed where its creation or its latest patch (an archive
  included) stands in the log: `changed_seq` is that event's place and
  `changed_at` its time. Nothing else moves them: linking the object,
  unlinking it, or a notice that it needs attention leaves them as they were.

  Only the projector writes here. Only the fleet's members read its objects
  (`Regents.Keyfleet.Graph.Checks.KeyReader`), except through the one read a fleet
  shows anyone: its open goals, each by title and project alone
  (`Regents.Keyfleet.Graph.shown/1`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Graph,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @text [trim?: false]

  postgres do
    table "graph_objects"
    schema("keyfleet_app")
    repo(Regents.Repo)

    # The workspace lists a fleet's objects, or one type of them, most
    # recently changed first, from the whole fleet or one project.
    custom_indexes do
      index([:fleet_id, :changed_seq, :id], name: "graph_objects_changed_index")
      index([:fleet_id, :type, :changed_seq, :id], name: "graph_objects_type_changed_index")

      index([:fleet_id, :project, :type, :changed_seq, :id],
        name: "graph_objects_project_changed_index",
        concurrently: true
      )

      # The words of the objects' fields, as a search matches them (`:search`),
      # for objects up to 250,000 bytes: Postgres holds at most 1MB of words for
      # one object, so a larger one is left out rather than refused.
      index(["jsonb_to_tsvector('english', data, '[\"string\"]')"],
        name: "graph_objects_search_index",
        using: "gin",
        where: "octet_length(data::text) <= 250000",
        concurrently: true
      )
    end

    references do
      reference(:cursor, on_delete: :delete)
    end
  end

  actions do
    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      argument :id, :string, allow_nil?: false, constraints: @text
      filter expr(fleet_id == ^arg(:fleet_id) and id == ^arg(:id))
      get? true
    end

    # A page of the fleet's workspace, the most recently changed first:
    # optionally one project's or one type of object only, and the archived
    # ones only when asked for. Each object comes with what its card shows,
    # not its text.
    read :cards do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text
      argument :type, :string, constraints: @text
      argument :include_archived?, :boolean, allow_nil?: false, default: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 (is_nil(^arg(:type)) or type == ^arg(:type)) and
                 (^arg(:include_archived?) or
                    fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys))
             )

      prepare build(
                sort: [changed_seq: :desc],
                select: [
                  :fleet_id,
                  :id,
                  :type,
                  :project,
                  :sys,
                  :version,
                  :changed_seq,
                  :changed_at
                ],
                load: [:title, :card, :review]
              )

      # Ties, which the log never makes, break the way the index reads back.
      pagination keyset?: true,
                 required?: true,
                 default_limit: 24,
                 max_page_size: 24,
                 stable_sort: [fleet_id: :desc, id: :desc]
    end

    # The fleet's open goals, or one project's, the most recently changed first: goals whose
    # status is `open`, not archived, and, for a starting goal, one of the
    # ideas every workspace begins with, joined by someone. Anyone may read
    # it, so each goal comes with its title and project alone. Callers bound
    # it with a limit.
    read :open_goals do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and type == "goal" and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys) and
                 fragment("(? ->> 'status') = 'open'", data) and
                 fragment(
                   "(? ->> 'starting' IS NULL OR jsonb_array_length(? -> 'joined') > 0)",
                   sys,
                   sys
                 )
             )

      prepare build(
                sort: [changed_seq: :desc],
                select: [:fleet_id, :id, :type, :project, :changed_seq, :changed_at],
                load: [:title]
              )
    end

    # A project's work as its page shows anyone, once the Key holding it shows
    # it to everyone (`Regents.Keyfleet.Projects.Project`): one part of it, the most
    # recently changed first, not archived. `goals` are its open goals,
    # `work` everything but goals and reviews, `outputs` its findings and its
    # accepted or reproduced tasks, `open` the tasks nobody has joined and the blocked ones,
    # which need someone's help. Each comes with its title, type, standing and
    # who made it alone. Callers bound it with a limit.
    read :shown do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text

      argument :part, :atom,
        allow_nil?: false,
        constraints: [one_of: [:goals, :work, :outputs, :open]]

      filter expr(
               fleet_id == ^arg(:fleet_id) and project == ^arg(:project) and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys) and
                 fragment(
                   "EXISTS (SELECT 1 FROM keyfleet_app.projects AS shown WHERE shown.fleet_id = ? AND shown.name = ? AND shown.state <> 'deleted' AND shown.shown_to_everyone)",
                   fleet_id,
                   project
                 ) and
                 ((^arg(:part) == :goals and type == "goal" and
                     fragment("(? ->> 'status') = 'open'", data)) or
                    (^arg(:part) == :work and type not in ["goal", "review"]) or
                    (^arg(:part) == :outputs and
                       (type == "finding" or
                          (type == "task" and review in ["accepted", "reproduced"]))) or
                    (^arg(:part) == :open and type == "task" and
                       (fragment("(? ->> 'progress') = 'blocked'", data) or
                          (fragment("(? ->> 'progress') = 'todo'", data) and
                             fragment("jsonb_array_length(? -> 'joined') = 0", sys)))))
             )

      prepare build(
                sort: [changed_seq: :desc],
                select: [:fleet_id, :id, :type, :project, :sys, :changed_seq, :changed_at],
                load: [:title, :standing]
              )
    end

    # The tasks that deliver on one of a shown project's goals (`implements`),
    # as its page shows anyone beside the goal, once the Key holding the
    # project shows it to everyone: the most recently changed first, not
    # archived, each with its title and standing alone. Callers bound it with
    # a limit.
    read :shown_goal_tasks do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text
      argument :goal, :string, allow_nil?: false, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and project == ^arg(:project) and type == "task" and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys) and
                 fragment(
                   "EXISTS (SELECT 1 FROM keyfleet_app.projects AS shown WHERE shown.fleet_id = ? AND shown.name = ? AND shown.state <> 'deleted' AND shown.shown_to_everyone)",
                   fleet_id,
                   project
                 ) and
                 fragment(
                   "? IN (SELECT link.source FROM keyfleet_app.graph_relations AS link WHERE link.fleet_id = ? AND link.target = ? AND link.type = 'implements')",
                   id,
                   ^arg(:fleet_id),
                   ^arg(:goal)
                 )
             )

      prepare build(
                sort: [changed_seq: :desc],
                select: [:fleet_id, :id, :type, :project, :changed_seq],
                load: [:title, :standing]
              )
    end

    # The fleet's items as its workspace's graph draws them, the most
    # recently changed first: optionally one project's, one type's or one
    # Key's (`owner_key`), or one goal's map (`goal`), and the archived ones
    # only when asked for. A goal's map is the goal, everything linked to it
    # either way, and around each task that delivers on it (`implements`)
    # what it produced, its reviews and its forks; an id that names no goal
    # has no map, and the goal comes first in its own map. Each comes with its
    # title, standing and owner alone. Callers bound it with a limit.
    read :graph do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text
      argument :type, :string, constraints: @text
      argument :owner_key, :integer, constraints: [min: 1]
      argument :goal, :string, constraints: @text
      argument :archived, :boolean, allow_nil?: false, default: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 (is_nil(^arg(:type)) or type == ^arg(:type)) and
                 (is_nil(^arg(:owner_key)) or owner_key == ^arg(:owner_key)) and
                 (is_nil(^arg(:goal)) or
                    (fragment(
                       "EXISTS (SELECT 1 FROM keyfleet_app.graph_objects AS goal WHERE goal.fleet_id = ? AND goal.id = ? AND goal.type = 'goal')",
                       ^arg(:fleet_id),
                       ^arg(:goal)
                     ) and
                       (id == ^arg(:goal) or
                          fragment(
                            """
                            ? IN (
                              SELECT link.source FROM keyfleet_app.graph_relations AS link
                              WHERE link.fleet_id = ? AND link.target = ?
                              UNION
                              SELECT link.target FROM keyfleet_app.graph_relations AS link
                              WHERE link.fleet_id = ? AND link.source = ?
                              UNION
                              SELECT made.target FROM keyfleet_app.graph_relations AS link
                              JOIN keyfleet_app.graph_relations AS made
                                ON made.fleet_id = link.fleet_id AND made.source = link.source
                                  AND made.type = 'produces'
                              WHERE link.fleet_id = ? AND link.target = ? AND link.type = 'implements'
                              UNION
                              SELECT around.source FROM keyfleet_app.graph_relations AS link
                              JOIN keyfleet_app.graph_relations AS around
                                ON around.fleet_id = link.fleet_id AND around.target = link.source
                                  AND around.type IN ('reviews', 'forks')
                              WHERE link.fleet_id = ? AND link.target = ? AND link.type = 'implements'
                            )
                            """,
                            id,
                            ^arg(:fleet_id),
                            ^arg(:goal),
                            ^arg(:fleet_id),
                            ^arg(:goal),
                            ^arg(:fleet_id),
                            ^arg(:goal),
                            ^arg(:fleet_id),
                            ^arg(:goal)
                          )))) and
                 (^arg(:archived) or
                    fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys))
             )

      prepare build(
                sort: [changed_seq: :desc],
                select: [:fleet_id, :id, :type, :project, :sys, :changed_seq, :changed_at],
                load: [:title, :standing, :owner_key]
              )

      # A goal's map always holds the goal, however much around it changed
      # since.
      prepare fn query, _context ->
        case Ash.Query.get_argument(query, :goal) do
          nil ->
            query

          goal ->
            Ash.Query.sort(query, [{Ash.Expr.calc(id == ^goal, type: :boolean), :desc}],
              prepend?: true
            )
        end
      end
    end

    # The fleet's goals and tasks, or one project's, archived ones left out,
    # for the workspace to count by where they stand
    # (`Regents.Keyfleet.Graph.tally/3`).
    read :tallied do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and type in ["goal", "task"] and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys)
             )
    end

    # The evidence that cites `uri` as its source and the tasks that name it
    # as their commit, the most recently changed first, archived ones
    # included.
    read :citing do
      argument :fleet_id, :string, allow_nil?: false
      argument :uri, :string, allow_nil?: false, constraints: @text
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 ((type == "evidence" and fragment("? ->> 'source_uri'", data) == ^arg(:uri)) or
                    (type == "task" and fragment("? ->> 'commit_ref'", data) == ^arg(:uri)))
             )

      prepare build(
                sort: [changed_seq: :desc],
                limit: 20,
                select: [:fleet_id, :id, :type, :data, :sys, :changed_seq, :changed_at],
                load: [:title, :card]
              )
    end

    # The tasks and evidence citing any of `uris` (the commits on a page of
    # history), with the field that cites each, for the page to mark.
    read :citing_any do
      argument :fleet_id, :string, allow_nil?: false
      argument :uris, {:array, :string}, allow_nil?: false, constraints: [max_length: 100]

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 ((type == "evidence" and
                     fragment("(? ->> 'source_uri') = ANY(?)", data, ^arg(:uris))) or
                    (type == "task" and
                       fragment("(? ->> 'commit_ref') = ANY(?)", data, ^arg(:uris))))
             )

      prepare build(
                sort: [changed_seq: :desc],
                limit: 500,
                select: [:fleet_id, :id, :type, :data, :sys, :changed_seq],
                load: [:title]
              )
    end

    # The tasks still in the workspace that name any of `uris` (the
    # notebooks a page shows) as their notebook, the most recently changed
    # first, as many as the Graph view draws, each with what its card shows
    # and when it was made.
    read :naming_notebooks do
      argument :fleet_id, :string, allow_nil?: false
      argument :uris, {:array, :string}, allow_nil?: false, constraints: [max_length: 200]

      filter expr(
               fleet_id == ^arg(:fleet_id) and type == "task" and
                 fragment("(? ->> 'notebook_ref') = ANY(?)", data, ^arg(:uris)) and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys)
             )

      prepare build(
                sort: [changed_seq: :desc],
                limit: 120,
                select: [:fleet_id, :id, :type, :data, :sys, :changed_seq, :changed_at],
                load: [:title, :standing, :owner_key, :created_at]
              )
    end

    # The work around one goal that is still in the workspace, the most
    # recently changed first: every object linked to the goal either way, and
    # what the tasks that deliver on it produced. Each comes with what its card
    # shows. One more than a goal's page lists is read, to tell there are more.
    read :around_goal do
      argument :fleet_id, :string, allow_nil?: false
      argument :goal_id, :string, allow_nil?: false, constraints: @text
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 fragment(
                   """
                   ? IN (
                     SELECT link.source FROM keyfleet_app.graph_relations AS link
                     WHERE link.fleet_id = ? AND link.target = ?
                     UNION
                     SELECT link.target FROM keyfleet_app.graph_relations AS link
                     WHERE link.fleet_id = ? AND link.source = ?
                     UNION
                     SELECT made.target FROM keyfleet_app.graph_relations AS link
                     JOIN keyfleet_app.graph_relations AS made
                       ON made.fleet_id = link.fleet_id AND made.source = link.source
                         AND made.type = 'produces'
                     WHERE link.fleet_id = ? AND link.target = ? AND link.type = 'implements'
                   )
                   """,
                   id,
                   ^arg(:fleet_id),
                   ^arg(:goal_id),
                   ^arg(:fleet_id),
                   ^arg(:goal_id),
                   ^arg(:fleet_id),
                   ^arg(:goal_id)
                 ) and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys)
             )

      prepare build(
                sort: [changed_seq: :desc],
                limit: 101,
                select: [:fleet_id, :id, :type, :sys, :changed_seq, :changed_at],
                load: [:title, :card, :standing]
              )
    end

    # The unfinished tasks one agent joined as one key of the fleet, newest
    # change first, each with what its card shows. A join made by the agent
    # of an earlier owner of the key is that agent's, not this one's.
    read :tasks_joined_by do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1]
      argument :wallet, :string, allow_nil?: false, constraints: @text
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and type == "task" and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 fragment(
                   "(? -> 'joined') @> jsonb_build_array(jsonb_build_object('key', jsonb_build_object('token_id', ?::bigint), 'wallet', ?::text))",
                   sys,
                   ^arg(:token_id),
                   ^arg(:wallet)
                 ) and
                 fragment("(? ->> 'progress') <> 'done'", data) and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys)
             )

      prepare build(
                sort: [changed_seq: :desc],
                limit: 20,
                select: [:fleet_id, :id, :type, :version],
                load: [:title, :card, :next_step]
              )
    end

    # The tasks awaiting review at their current version that one Key, acting
    # at its current ownership from one wallet, may review now: the oldest
    # wait first, a page of at most 20 with how many wait in all. A task's
    # wait began when its current version was made (`changed_at`). "May
    # review" is the graph host's rule for a review (`_plan_review` in
    # graph_host/src/keyfleet_graph/host.py), and this read keeps to it: a
    # task not archived, in a project that is active, that
    # neither the Key nor the wallet submitted, that the Key has not joined
    # at its current ownership, and that the Key did not change or submit
    # (`sys.worked`, which never lists the task's creator). A task awaiting
    # review has no review of its current version, so the Key has not
    # reviewed it either. A task never submitted has no `submitted` to
    # compare, so it is left out.
    read :review_queue do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1]
      argument :ownership_epoch, :integer, allow_nil?: false, constraints: [min: 1]
      argument :wallet, :string, allow_nil?: false, constraints: @text
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and type == "task" and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 review == "awaiting_review" and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys) and
                 fragment(
                   "EXISTS (SELECT 1 FROM keyfleet_app.projects AS open WHERE open.fleet_id = ? AND open.name = ? AND open.state = 'active')",
                   fleet_id,
                   project
                 ) and
                 fragment(
                   "(? #>> '{submitted,key,token_id}')::bigint <> ?",
                   sys,
                   ^arg(:token_id)
                 ) and
                 fragment("(? #>> '{submitted,wallet}') <> ?", sys, ^arg(:wallet)) and
                 fragment(
                   "NOT COALESCE(? -> 'joined', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('key', jsonb_build_object('token_id', ?::bigint), 'ownership_epoch', ?::bigint))",
                   sys,
                   ^arg(:token_id),
                   ^arg(:ownership_epoch)
                 ) and
                 fragment(
                   "NOT COALESCE(? -> 'worked', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('key', jsonb_build_object('token_id', ?::bigint)))",
                   sys,
                   ^arg(:token_id)
                 )
             )

      prepare build(
                sort: [changed_seq: :asc, id: :asc],
                select: [:fleet_id, :id, :type, :version, :changed_seq, :changed_at],
                load: [:title]
              )

      pagination offset?: true,
                 countable: :by_default,
                 required?: true,
                 default_limit: 20,
                 max_page_size: 20
    end

    # The tasks awaiting review at their current version, the project's or the
    # whole fleet's, archived ones left out, the longest wait first: a task's
    # wait began when its current version was made (`changed_at`). Callers
    # bound it with a limit.
    read :awaiting_review do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and type == "task" and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 review == "awaiting_review" and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys)
             )

      prepare build(
                sort: [changed_seq: :asc, id: :asc],
                select: [:fleet_id, :id, :type, :project, :version, :changed_seq, :changed_at],
                load: [:title]
              )
    end

    # The goals a Key and wallet of the fleet joined and that are still in the
    # workspace, newest change first.
    read :joined_by do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1]
      argument :wallet, :string, allow_nil?: false, constraints: @text
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and type == "goal" and
                 (is_nil(^arg(:project)) or project == ^arg(:project)) and
                 fragment(
                   "(? -> 'joined') @> jsonb_build_array(jsonb_build_object('key', jsonb_build_object('token_id', ?::bigint), 'wallet', ?::text))",
                   sys,
                   ^arg(:token_id),
                   ^arg(:wallet)
                 ) and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys)
             )

      prepare build(
                sort: [changed_seq: :desc],
                limit: 20,
                select: [:fleet_id, :id, :type, :version],
                load: [:title, :card]
              )
    end

    # The titles of a few of the fleet's objects, to name the objects a page
    # mentions.
    read :titled do
      argument :fleet_id, :string, allow_nil?: false

      argument :ids, {:array, :string},
        allow_nil?: false,
        constraints: [items: @text, max_length: 200]

      filter expr(fleet_id == ^arg(:fleet_id) and id in ^arg(:ids))
      prepare build(select: [:fleet_id, :id, :type, :sys], load: [:title])
    end

    # A chosen few of one project's objects, archived ones left out, each
    # whole, with its review and the Key it belongs to, for a packet of them
    # (`Regents.Keyfleet.Graph.Workspace`).
    read :selected do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text

      argument :ids, {:array, :string},
        allow_nil?: false,
        constraints: [items: @text, max_length: 20]

      filter expr(
               fleet_id == ^arg(:fleet_id) and project == ^arg(:project) and id in ^arg(:ids) and
                 fragment("(? ->> 'archived') IS DISTINCT FROM 'true'", sys)
             )

      prepare build(load: [:review, :owner_key])
    end

    # The fleet's objects whose words match a search, in any of their text
    # fields, a page at a time (`Regents.Keyfleet.Search`), each at the time it last
    # changed. Words are matched as English, through the objects' search
    # index (`graph_objects_search_index`), which holds objects up to
    # 250,000 bytes.
    read :search do
      argument :fleet_id, :string, allow_nil?: false
      argument :query, :string, allow_nil?: false, constraints: [max_length: 200, trim?: false]
      argument :before_at, :utc_datetime_usec
      argument :before_kind, :string
      argument :before_id, :string
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 200]

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 fragment(
                   ~S|octet_length(?::text) <= 250000 AND jsonb_to_tsvector('english', ?, '["string"]') @@ websearch_to_tsquery('english', ?)|,
                   data,
                   data,
                   ^arg(:query)
                 )
             )

      prepare build(
                select: [:fleet_id, :id, :type, :project, :sys, :changed_at],
                load: [:title, :changed, match: [query: arg(:query)]]
              )

      prepare {Regents.Keyfleet.Preparations.SearchPage,
               kind: "item", at: :changed, id: :id_in_byte_order}
    end

    read :with_ids do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :ids, {:array, :string}, allow_nil?: false, constraints: [items: @text]
      filter expr(fleet_id == ^arg(:fleet_id) and id in ^arg(:ids))
    end

    # Every object of one project, for its deletion.
    read :of_project do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))
    end

    destroy :forget do
      public? false
    end

    create :project do
      public? false
      accept [:fleet_id, :id, :type, :project, :data, :sys, :version, :changed_seq, :changed_at]
      upsert? true
      upsert_fields [:type, :data, :sys, :version, :changed_seq, :changed_at]
    end
  end

  policies do
    # The open goals a fleet shows anyone, and the work of the projects shown
    # to everyone, with the tasks that deliver on their goals.
    policy action([:open_goals, :shown, :shown_goal_tasks]) do
      authorize_if always()
    end

    policy action([
             :in_fleet,
             :titled,
             :selected,
             :cards,
             :graph,
             :tallied,
             :around_goal,
             :tasks_joined_by,
             :review_queue,
             :awaiting_review,
             :joined_by,
             :citing,
             :citing_any,
             :naming_notebooks,
             :search
           ]) do
      authorize_if Regents.Keyfleet.Graph.Checks.KeyReader
    end

    policy action([:with_ids, :project, :of_project, :forget]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true

    attribute :id, :string,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      constraints: @text

    attribute :type, :string, allow_nil?: false, public?: true, constraints: @text
    # Set when the object is made, and never changed.
    attribute :project, :string, allow_nil?: false, public?: true, constraints: @text
    attribute :data, :map, allow_nil?: false, public?: true
    attribute :sys, :map, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, public?: true, constraints: [min: 1]

    attribute :changed_seq, Regents.Keyfleet.Graph.Seq, allow_nil?: false, public?: true

    attribute :changed_at, :string, allow_nil?: false, public?: true, constraints: @text
  end

  calculations do
    # When the object last changed, as a time (`changed_at` is the log's own text).
    calculate :changed, :utc_datetime_usec, expr(fragment("(?::timestamptz)", changed_at))

    # When the object was made: the time of the log's event that made it,
    # read through the events' index on the object they name. Page data
    # only; agents read an object's history instead.
    calculate :created_at,
              :string,
              expr(
                fragment(
                  """
                  (SELECT e.timestamp FROM keyfleet_app.graph_events AS e
                   WHERE e.fleet_id = ? AND (e.payload ->> 'id') = ? AND e.type = 'object.created'
                   ORDER BY e.seq LIMIT 1)
                  """,
                  fleet_id,
                  id
                )
              )

    # The id in byte order, as a search orders objects that changed at once.
    calculate :id_in_byte_order, :string, expr(fragment("(? COLLATE \"C\")", id))

    # The words around what a search matched in the object's text fields, at
    # most 24 of them.
    calculate :match,
              :string,
              expr(
                fragment(
                  ~S|ts_headline('english', (SELECT string_agg(field #>> '{}', ' ') FROM jsonb_path_query(?, 'strict $.**') AS field WHERE jsonb_typeof(field) = 'string'), websearch_to_tsquery('english', ?), 'StartSel="", StopSel="", MaxWords=24, MinWords=8')|,
                  data,
                  ^arg(:query)
                )
              ) do
      argument :query, :string, allow_nil?: false, constraints: [trim?: false]
    end

    # A review has no title of its own; it is named by its decision and, when
    # the reviewer tried, whether the work reproduced.
    calculate :title,
              :string,
              expr(
                fragment(
                  """
                  left(CASE ? WHEN 'review' THEN
                    CASE ? ->> 'decision' WHEN 'accept' THEN 'Review: accepted' WHEN 'dispute' THEN 'Review: disputed' END
                    || CASE ? ->> 'reproduction' WHEN 'passed' THEN ', reproduced' WHEN 'failed' THEN ', didn’t reproduce' ELSE '' END
                  ELSE ? ->> 'title' END, 200)
                  """,
                  type,
                  data,
                  data,
                  data
                )
              ),
              public?: true

    # Where a submitted task's review stands; nothing for any other object.
    # The reviews of a task are the `reviews` links to it, read through the
    # links' index on their target.
    calculate :review,
              :string,
              expr(
                fragment(
                  """
                  CASE WHEN ? = 'task' AND (? ->> 'progress') = 'done' THEN COALESCE((
                    SELECT CASE
                      WHEN bool_or((review.data ->> 'decision') = 'dispute') THEN 'disputed'
                      WHEN bool_or((review.data ->> 'decision') = 'accept'
                        AND (review.data ->> 'reproduction') = 'passed') THEN 'reproduced'
                      WHEN bool_or((review.data ->> 'decision') = 'accept') THEN 'accepted'
                    END
                    FROM keyfleet_app.graph_relations AS link
                    JOIN keyfleet_app.graph_objects AS review
                      ON review.fleet_id = link.fleet_id AND review.id = link.source
                    WHERE link.fleet_id = ? AND link.target = ? AND link.type = 'reviews'
                      AND (review.sys #>> '{review,task_version}')::bigint = ?
                  ), 'awaiting_review') END
                  """,
                  type,
                  data,
                  fleet_id,
                  id,
                  version
                )
              ),
              public?: true

    # The Key an object belongs to: the Key that created it; none for a
    # starting goal. The Keys that joined a task work on it too (`sys.joined`).
    calculate :owner_key,
              :integer,
              expr(fragment("(? #>> '{created_by,key,token_id}')::bigint", sys)),
              public?: true

    # A task's next step as its author wrote it; nothing for any other object.
    calculate :next_step, :string, expr(fragment("? ->> 'next_step'", data)), public?: true

    # A goal's status, a task's progress or, once it is submitted, its
    # review; nothing for any other object.
    calculate :standing,
              :string,
              expr(
                fragment(
                  "COALESCE(?, left(CASE ? WHEN 'goal' THEN ? ->> 'status' WHEN 'task' THEN ? ->> 'progress' END, 32))",
                  review,
                  type,
                  data,
                  data
                )
              ),
              public?: true

    # The few short fields a card shows, and the start of the object's main
    # text, cut in the database so a page of cards never loads whole texts.
    calculate :card,
              :map,
              expr(
                fragment(
                  """
                  jsonb_strip_nulls(jsonb_build_object(
                    'status', left(? ->> 'status', 32),
                    'progress', left(? ->> 'progress', 32),
                    'confidence', left(? ->> 'confidence', 32),
                    'customer', left(? ->> 'customer', 200),
                    'payment_asset', left(? ->> 'payment_asset', 32),
                    'price_proposal', left(? ->> 'price_proposal', 100),
                    'source_uri', left(? ->> 'source_uri', 512),
                    'commit_ref', left(? ->> 'commit_ref', 512),
                    'notebook_ref', left(? ->> 'notebook_ref', 512),
                    'result_ref', left(? ->> 'result_ref', 512),
                    'gist', left(CASE ?
                      WHEN 'goal' THEN ? ->> 'outcome'
                      WHEN 'task' THEN COALESCE(? ->> 'next_step', ? ->> 'deliverable')
                      WHEN 'finding' THEN ? ->> 'statement'
                      WHEN 'evidence' THEN ? ->> 'excerpt'
                      WHEN 'service' THEN ? ->> 'problem'
                      WHEN 'note' THEN ? ->> 'body'
                      WHEN 'dead_end' THEN ? ->> 'why_it_failed'
                      WHEN 'review' THEN ? ->> 'rationale'
                    END, 240)))
                  """,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data,
                  type,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data,
                  data
                )
              ),
              public?: true
  end

  relationships do
    belongs_to :cursor, Regents.Keyfleet.Graph.Cursor do
      source_attribute :fleet_id
      destination_attribute :fleet_id
      define_attribute? false
    end
  end
end
