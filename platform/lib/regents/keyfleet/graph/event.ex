defmodule Regents.Keyfleet.Graph.Event do
  @moduledoc """
  One event of a fleet's graph log, copied at its place (`seq`) in the log.

  Only the events that change the workspace, the attention each write asks
  for and the command record each write leaves are copied; the runtime's own
  bookkeeping is not. Each keeps the projects whose items it touched
  (`projects`), so a member reads one project's changes, and each keeps
  `byte_size`, the length of the event as a reader receives it, so a page of
  events is cut to size by the database. Only the projector writes here. Only
  the fleet's members read its events (`Regents.Keyfleet.Graph.Checks.KeyReader`),
  except which of its changes are notable, when, as which Key and in which
  projects, which the workspace pulse shows anyone without any text an event
  holds.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Graph,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  @bigint 9_223_372_036_854_775_807
  @text [trim?: false]
  # A page stops at this many bytes of events, or after its first event when
  # that one alone is larger.
  @page_bytes 512 * 1024
  # How many of the latest changes the workspace page lists.
  @activity 30
  # How many of one object's changes its page lists at a time.
  @history 50
  @brief_fields [:fleet_id, :seq, :type, :actor, :timestamp]
  @member ~r/\Amember:[0-9]+:0x[0-9a-f]{40}:([0-9]+)@[0-9]+\/(human|agent):(0x[0-9a-f]{40})\z/

  # The changes worth telling people who watch a fleet: every new object; a
  # patch that moves a status or progress, archives an object, changes a goal
  # or service, or is a member joining or leaving a task; and a link saying that
  # one object supports, contradicts or produces another. Edits to other
  # objects' words, unlinks, attention notices and command records are left
  # out. The same words make the partial index and the reads that use it, so
  # the index answers exactly the events that match.
  @notable """
  type = 'object.created' OR (type = 'relation.created' AND (payload #>> '{relation,type}') IN ('contradicts', 'supports', 'produces')) OR (type = 'patch.applied' AND (jsonb_exists_any(payload -> 'diff', ARRAY['status', 'progress']) OR ((payload #> '{diff,sys,new,archived}') = 'true'::jsonb AND (payload #> '{diff,sys,old,archived}') IS DISTINCT FROM 'true'::jsonb) OR split_part(payload ->> 'target', '#', 1) IN ('goal', 'service') OR (actor LIKE 'member:%' AND split_part(payload ->> 'target', '#', 1) = 'task' AND (payload #> '{diff,sys,new,joined}') IS DISTINCT FROM (payload #> '{diff,sys,old,joined}'))))\
  """

  postgres do
    table "graph_events"
    schema("keyfleet_app")
    repo(Regents.Repo)

    references do
      reference(:cursor, on_delete: :delete)
    end

    # The workspace pages find an object's events by the ids their payloads
    # name: an object's creation and links by `id`, its changes and links to
    # it by `target`, and links from it by `source`.
    custom_indexes do
      index(["fleet_id", "(payload ->> 'id')", "seq"], name: "graph_events_payload_id_index")

      index(["fleet_id", "(payload ->> 'target')", "seq"],
        name: "graph_events_payload_target_index"
      )

      index(["fleet_id", "(payload ->> 'source')", "seq"],
        name: "graph_events_payload_source_index"
      )

      # The fleet's notable changes, newest first, for its activity.
      index(["fleet_id", "seq DESC"],
        name: "graph_events_activity_index",
        where: @notable,
        concurrently: true
      )

      # The record each write left of itself, by its command id.
      index(["fleet_id", "(payload ->> 'command_id')"],
        name: "graph_events_command_id_index",
        where: "type = 'keyfleet.command'",
        concurrently: true
      )
    end
  end

  @doc "The most bytes of events one page of changes holds."
  def page_bytes, do: @page_bytes

  actions do
    # The events after one place in the log, oldest first, the whole fleet's
    # or one project's: at most `limit` of them, and no more than `max_bytes`
    # of them unless the first alone is larger. The cut is found from the
    # recorded sizes inside the query, so only the page's own rows are loaded.
    read :page do
      argument :fleet_id, :string, allow_nil?: false
      argument :after_seq, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 500]
      argument :project, :string, constraints: @text

      argument :max_bytes, :integer,
        allow_nil?: false,
        default: @page_bytes,
        constraints: [min: 1, max: @page_bytes]

      filter expr(
               fleet_id == ^arg(:fleet_id) and seq > ^arg(:after_seq) and
                 (is_nil(^arg(:project)) or fragment("? = ANY(?)", ^arg(:project), projects)) and
                 seq <=
                   fragment(
                     "(SELECT COALESCE(max(p.seq) FILTER (WHERE p.total <= ?), min(p.seq)) FROM (SELECT e.seq, sum(e.byte_size) OVER (ORDER BY e.seq) AS total FROM keyfleet_app.graph_events AS e WHERE e.fleet_id = ? AND e.seq > ? AND (?::text IS NULL OR ?::text = ANY(e.projects)) ORDER BY e.seq LIMIT ?) AS p)",
                     ^arg(:max_bytes),
                     ^arg(:fleet_id),
                     ^arg(:after_seq),
                     ^arg(:project),
                     ^arg(:project),
                     ^arg(:limit)
                   )
             )

      prepare fn query, _context ->
        query
        |> Ash.Query.unset([:sort, :limit, :offset])
        |> Ash.Query.sort(seq: :asc)
        |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
      end
    end

    # Every change to one object after one place in the log, oldest first, at
    # most `limit` of them: its creation, its edits and archiving, the links
    # made to or from it, a review's of a task included, and those links'
    # removals. Each kind is looked up on its own index from `after_seq` on,
    # as `:history` looks them up back from the newest.
    read :about_object do
      argument :fleet_id, :string, allow_nil?: false
      argument :object_id, :string, allow_nil?: false, constraints: @text
      argument :after_seq, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 501]

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 fragment(
                   """
                   ? = ANY(ARRAY(
                     (SELECT e.seq FROM keyfleet_app.graph_events AS e
                      WHERE e.fleet_id = ? AND (e.payload ->> 'id') = ? AND e.type = 'object.created' AND e.seq > ?
                      ORDER BY e.seq LIMIT ?)
                     UNION ALL
                     (SELECT e.seq FROM keyfleet_app.graph_events AS e
                      WHERE e.fleet_id = ? AND (e.payload ->> 'target') = ? AND e.type IN ('patch.applied', 'relation.created') AND e.seq > ?
                      ORDER BY e.seq LIMIT ?)
                     UNION ALL
                     (SELECT e.seq FROM keyfleet_app.graph_events AS e
                      WHERE e.fleet_id = ? AND (e.payload ->> 'source') = ? AND e.type = 'relation.created' AND e.seq > ?
                      ORDER BY e.seq LIMIT ?)
                     UNION ALL
                     (SELECT d.seq
                      FROM keyfleet_app.graph_events AS r
                      CROSS JOIN LATERAL (
                        SELECT d.seq FROM keyfleet_app.graph_events AS d
                        WHERE d.fleet_id = r.fleet_id AND (d.payload ->> 'id') = (r.payload ->> 'id') AND d.type = 'relation.removed' AND d.seq > ?
                        LIMIT 1
                      ) AS d
                      WHERE r.fleet_id = ? AND r.type = 'relation.created' AND ((r.payload ->> 'source') = ? OR (r.payload ->> 'target') = ?)
                      ORDER BY d.seq LIMIT ?)))
                   """,
                   seq,
                   ^arg(:fleet_id),
                   ^arg(:object_id),
                   ^arg(:after_seq),
                   ^arg(:limit),
                   ^arg(:fleet_id),
                   ^arg(:object_id),
                   ^arg(:after_seq),
                   ^arg(:limit),
                   ^arg(:fleet_id),
                   ^arg(:object_id),
                   ^arg(:after_seq),
                   ^arg(:limit),
                   ^arg(:after_seq),
                   ^arg(:fleet_id),
                   ^arg(:object_id),
                   ^arg(:object_id),
                   ^arg(:limit)
                 )
             )

      prepare fn query, _context ->
        query
        |> Ash.Query.unset([:sort, :limit, :offset])
        |> Ash.Query.sort(seq: :asc)
        |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
      end
    end

    # The fleet's latest changes, or one project's, newest first, for its
    # workspace page. The record each write leaves of itself is left out: the
    # changes it made are listed on their own. So is a review's link to its
    # task, which the review's own creation already tells.
    read :activity do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and type != "keyfleet.command" and
                 (is_nil(^arg(:project)) or fragment("? = ANY(?)", ^arg(:project), projects)) and
                 not (type == "relation.created" and
                        fragment("(? #>> '{relation,type}') = 'reviews'", payload))
             )

      prepare fn query, _context ->
        query
        |> Ash.Query.unset([:sort, :limit, :offset])
        |> Ash.Query.sort(seq: :desc)
        |> Ash.Query.limit(@activity)
        |> Ash.Query.select(@brief_fields)
        |> Ash.Query.load(:brief)
      end
    end

    # The fleet's notable changes before `before_seq` (from the newest when
    # nil), newest first, `limit` at most, each with what a line about it
    # needs and not the text it carries. `keys` and `wallet` keep the changes
    # made as those Keys or by that wallet (`Regents.Keyfleet.Preparations.DoneBy`).
    read :notable_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_seq, :integer, constraints: [min: 1, max: @bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 200]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

      filter expr(fleet_id == ^arg(:fleet_id))

      prepare fn query, _context -> Ash.Query.filter(query, ^sql(@notable)) end

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [seq: :desc], before: [:before_seq]}

      prepare {Regents.Keyfleet.Preparations.DoneBy, member: :actor}
      prepare build(select: [:projects | @brief_fields], load: [:brief])
    end

    # The fleet's notable changes after `after_seq`, oldest first, `limit` at
    # most, each with what a line about it needs and not the text it carries.
    read :notable_after do
      argument :fleet_id, :string, allow_nil?: false
      argument :after_seq, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 200]

      filter expr(fleet_id == ^arg(:fleet_id) and seq > ^arg(:after_seq))

      prepare fn query, _context -> Ash.Query.filter(query, ^sql(@notable)) end

      prepare fn query, _context ->
        Ash.Query.before_action(query, fn query ->
          query
          |> Ash.Query.unset([:sort, :limit, :offset])
          |> Ash.Query.sort(seq: :asc)
          |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
        end)
      end

      prepare build(select: [:projects | @brief_fields], load: [:brief])
    end

    # Every change to one object up to `through_seq`, newest first, one more
    # than a page so the reader knows whether more come before: its creation,
    # its edits and archiving, and the links made to or from it and removed
    # again. A task's reviews are told by their links to it; a review's own
    # link to its task is left out of the review's history, which its
    # creation already tells. Each kind of change is looked up on its own index and cut to that
    # many before they are merged, so a page reads only the object's own rows:
    # a removed link is found from each link the object ever had, one lookup
    # apiece, since a link is removed at most once.
    read :history do
      argument :fleet_id, :string, allow_nil?: false
      argument :object_id, :string, allow_nil?: false, constraints: @text

      argument :through_seq, :integer,
        allow_nil?: false,
        default: @bigint,
        constraints: [min: 0, max: @bigint]

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 fragment(
                   """
                   ? = ANY(ARRAY(
                     (SELECT e.seq FROM keyfleet_app.graph_events AS e
                      WHERE e.fleet_id = ? AND (e.payload ->> 'id') = ? AND e.type = 'object.created' AND e.seq <= ?
                      ORDER BY e.seq DESC LIMIT ?)
                     UNION ALL
                     (SELECT e.seq FROM keyfleet_app.graph_events AS e
                      WHERE e.fleet_id = ? AND (e.payload ->> 'target') = ? AND e.type IN ('patch.applied', 'relation.created') AND e.seq <= ?
                      ORDER BY e.seq DESC LIMIT ?)
                     UNION ALL
                     (SELECT e.seq FROM keyfleet_app.graph_events AS e
                      WHERE e.fleet_id = ? AND (e.payload ->> 'source') = ? AND e.type = 'relation.created' AND (e.payload #>> '{relation,type}') <> 'reviews' AND e.seq <= ?
                      ORDER BY e.seq DESC LIMIT ?)
                     UNION ALL
                     (SELECT d.seq
                      FROM keyfleet_app.graph_events AS r
                      CROSS JOIN LATERAL (
                        SELECT d.seq FROM keyfleet_app.graph_events AS d
                        WHERE d.fleet_id = r.fleet_id AND (d.payload ->> 'id') = (r.payload ->> 'id') AND d.type = 'relation.removed' AND d.seq > r.seq AND d.seq <= ?
                        LIMIT 1
                      ) AS d
                      WHERE r.fleet_id = ? AND r.type = 'relation.created' AND ((r.payload ->> 'source') = ? OR (r.payload ->> 'target') = ?)
                      ORDER BY d.seq DESC LIMIT ?)))
                   """,
                   seq,
                   ^arg(:fleet_id),
                   ^arg(:object_id),
                   ^arg(:through_seq),
                   ^(@history + 1),
                   ^arg(:fleet_id),
                   ^arg(:object_id),
                   ^arg(:through_seq),
                   ^(@history + 1),
                   ^arg(:fleet_id),
                   ^arg(:object_id),
                   ^arg(:through_seq),
                   ^(@history + 1),
                   ^arg(:through_seq),
                   ^arg(:fleet_id),
                   ^arg(:object_id),
                   ^arg(:object_id),
                   ^(@history + 1)
                 )
             )

      prepare build(
                sort: [seq: :desc],
                limit: @history + 1,
                select: @brief_fields,
                load: [:brief]
              )
    end

    # The record a write left of itself under one command id, from every Key
    # it was sent as: the caller keeps those of its own wallet
    # (`RegentsWeb.Keyfleet.AgentReceiptController`). The type is written out so
    # `graph_events_command_id_index` serves every plan of it.
    read :command do
      argument :fleet_id, :string, allow_nil?: false
      argument :command_id, :string, allow_nil?: false, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and fragment("? = 'keyfleet.command'", type) and
                 fragment("(? ->> 'command_id') = ?", payload, ^arg(:command_id))
             )

      prepare build(sort: [seq: :asc], limit: 20)
    end

    # The events a page's command records name that an earlier page copied.
    read :with_event_ids do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :event_ids, {:array, :string}, allow_nil?: false, constraints: [items: @text]
      filter expr(fleet_id == ^arg(:fleet_id) and event_id in ^arg(:event_ids))
    end

    # Every event the fleet's log took before `before`, by the log's own
    # clock, for counting how large its workspace record stood then
    # (`Regents.Keyfleet.Graph.record_size/2`).
    read :taken_before do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :before, :utc_datetime_usec, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 fragment("(?::timestamptz) < ?", timestamp, ^arg(:before))
             )
    end

    # The creations and patches of items after `after_seq`, oldest first, a
    # batch at a time, for counting them into the Atlas
    # (`Regents.Keyfleet.Atlas.Fill`). The primary key finds them.
    read :changes_after do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :after_seq, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]

      filter expr(
               fleet_id == ^arg(:fleet_id) and seq > ^arg(:after_seq) and
                 type in ["object.created", "patch.applied"]
             )

      prepare build(sort: [seq: :asc], limit: 2_000)
    end

    # Every change that touched one project, for its deletion.
    read :of_project do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: @text

      filter expr(
               fleet_id == ^arg(:fleet_id) and fragment("? = ANY(?)", ^arg(:project), projects)
             )
    end

    destroy :forget do
      public? false
    end

    create :record do
      public? false
      accept [:fleet_id, :seq, :event_id, :type, :actor, :timestamp, :payload, :projects]
      upsert? true
      upsert_fields [:event_id, :type, :actor, :timestamp, :payload, :projects, :byte_size]

      change fn changeset, _context ->
        encoded = changeset.attributes |> view() |> Jason.encode_to_iodata!()
        Ash.Changeset.force_change_attribute(changeset, :byte_size, IO.iodata_length(encoded))
      end
    end
  end

  policies do
    # Which changes are notable, and when, without their words: the
    # workspace pulse shows anyone that much.
    policy action([:notable_before, :notable_after]) do
      authorize_if always()
    end

    policy action([:page, :about_object, :activity, :history, :command]) do
      authorize_if Regents.Keyfleet.Graph.Checks.KeyReader
    end

    policy action([
             :record,
             :with_event_ids,
             :taken_before,
             :changes_after,
             :of_project,
             :forget
           ]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true

    attribute :seq, :integer,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :event_id, :string, allow_nil?: false, public?: true, constraints: @text
    attribute :type, :string, allow_nil?: false, public?: true, constraints: @text
    attribute :actor, :string, allow_nil?: false, public?: true, constraints: @text
    attribute :timestamp, :string, allow_nil?: false, public?: true, constraints: @text
    attribute :payload, :map, allow_nil?: false, public?: true

    # The projects whose items the change touched: an item's creation or
    # change, its project; a link, both ends'; a write's own record, every
    # project its changes touched.
    attribute :projects, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :byte_size, :integer, allow_nil?: false, constraints: [min: 1]
  end

  calculations do
    # What a line about the event needs from it, read in the database so a
    # page of lines never loads the text the event carries:
    #   object.created   object, object_type, and for a review its
    #                    decision and the task it reviews
    #   patch.applied    object, fields (the names changed), archived (the
    #                    patch archived it), joins (how many members joined
    #                    it, or less than 0 for how many left),
    #                    submitted (the patch submitted a task for review),
    #                    and values: {old, new} of the few short fields shown
    #   relation.created relation_type, source, target, and for a review's
    #                    link to its task the review's decision
    #   relation.removed the same, from the event that made the link
    #   keyfleet.attention kind, object
    # Any other event answers an empty map.
    calculate :brief,
              :map,
              expr(
                fragment(
                  """
                  CASE ?
                  WHEN 'object.created' THEN jsonb_strip_nulls(jsonb_build_object('object', ? #>> '{object,id}', 'object_type', ? #>> '{object,type}', 'decision', ? #>> '{object,data,decision}', 'task', ? #>> '{object,data,sys,review,task}'))
                  WHEN 'patch.applied' THEN jsonb_build_object(
                    'object', (? ->> 'target'),
                    'fields', CASE WHEN jsonb_typeof(? -> 'diff') = 'object'
                      THEN (SELECT COALESCE(jsonb_agg(k.key ORDER BY k.key), '[]'::jsonb) FROM jsonb_object_keys(? -> 'diff') AS k(key))
                      ELSE '[]'::jsonb END,
                    'archived', COALESCE((? #> '{diff,sys,new,archived}') = 'true'::jsonb AND (? #> '{diff,sys,old,archived}') IS DISTINCT FROM 'true'::jsonb, false),
                    'joins', (SELECT CASE WHEN j.added > 0 THEN j.added ELSE -j.removed END FROM (SELECT
                      (SELECT count(*) FROM jsonb_array_elements(COALESCE(? #> '{diff,sys,new,joined}', '[]'::jsonb)) AS e(m) WHERE NOT COALESCE(? #> '{diff,sys,old,joined}', '[]'::jsonb) @> jsonb_build_array(e.m)) AS added,
                      (SELECT count(*) FROM jsonb_array_elements(COALESCE(? #> '{diff,sys,old,joined}', '[]'::jsonb)) AS e(m) WHERE NOT COALESCE(? #> '{diff,sys,new,joined}', '[]'::jsonb) @> jsonb_build_array(e.m)) AS removed) AS j),
                    'submitted', (? #> '{diff,sys,new,submitted,version}') IS NOT NULL AND (? #> '{diff,sys,new,submitted,version}') IS DISTINCT FROM (? #> '{diff,sys,old,submitted,version}'),
                    'values', jsonb_strip_nulls(jsonb_build_object(
                      'status', ? #> '{diff,status}',
                      'progress', ? #> '{diff,progress}',
                      'confidence', ? #> '{diff,confidence}')))
                  WHEN 'relation.created' THEN jsonb_strip_nulls(jsonb_build_object('relation_type', ? #>> '{relation,type}', 'source', (? ->> 'source'), 'target', (? ->> 'target'),
                    'decision', CASE WHEN (? #>> '{relation,type}') = 'reviews' THEN
                      (SELECT o.payload #>> '{object,data,decision}' FROM keyfleet_app.graph_events AS o
                       WHERE o.fleet_id = ? AND (o.payload ->> 'id') = (? ->> 'source') AND o.type = 'object.created'
                       ORDER BY o.seq LIMIT 1) END))
                  WHEN 'relation.removed' THEN
                    (SELECT jsonb_build_object('relation_type', r.payload #>> '{relation,type}', 'source', (r.payload ->> 'source'), 'target', (r.payload ->> 'target'))
                     FROM keyfleet_app.graph_events AS r
                     WHERE r.fleet_id = ? AND r.type = 'relation.created' AND (r.payload ->> 'id') = (? ->> 'id')
                     ORDER BY r.seq DESC LIMIT 1)
                  WHEN 'keyfleet.attention' THEN jsonb_build_object('kind', ? ->> 'kind', 'object', ? ->> 'object_id')
                  ELSE '{}'::jsonb
                  END
                  """,
                  type,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  payload,
                  fleet_id,
                  payload,
                  fleet_id,
                  payload,
                  payload,
                  payload
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

  # A fragment of SQL kept in one module attribute, so the same words can
  # make an index and the reads that use it; the expression macro takes only
  # literal SQL.
  defp sql(sql) do
    {:ok, fragment} = Ash.Query.Function.Fragment.new([sql])
    fragment
  end

  @doc """
  The member an event's `actor` names, as `{token_id, kind, wallet}`: the Key
  it wrote as, `"human"` or `"agent"`, and the wallet that signed; nil for
  the workspace's own doing.
  """
  def member(actor) do
    case Regex.run(@member, actor, capture: :all_but_first) do
      [token_id, kind, wallet] -> {String.to_integer(token_id), kind, wallet}
      nil -> nil
    end
  end

  @doc "The event as a reader receives it."
  def view(event) do
    %{
      seq: event.seq,
      id: event.event_id,
      type: event.type,
      actor: event.actor,
      timestamp: event.timestamp,
      payload: event.payload
    }
  end
end
