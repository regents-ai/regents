defmodule Regents.Repo.Migrations.KeyfleetTaskJoinsActivityIndex do
  @moduledoc """
  The fleet activity's index of the graph events worth telling, under a new
  name: a task's assignee no longer exists, and a member joining or leaving
  a task is told as joining a goal is. The new index is built beside the old
  one and the old one dropped after it, both concurrently, so the table is
  never locked against writes and activity reads always have an index.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:graph_events, ["fleet_id", "seq DESC"],
             name: "graph_events_activity_index",
             concurrently: true,
             where:
               "type = 'object.created' OR (type = 'relation.created' AND (payload #>> '{relation,type}') IN ('contradicts', 'supports', 'produces')) OR (type = 'patch.applied' AND (jsonb_exists_any(payload -> 'diff', ARRAY['status', 'progress']) OR ((payload #> '{diff,sys,new,archived}') = 'true'::jsonb AND (payload #> '{diff,sys,old,archived}') IS DISTINCT FROM 'true'::jsonb) OR split_part(payload ->> 'target', '#', 1) IN ('goal', 'service') OR (actor LIKE 'member:%' AND split_part(payload ->> 'target', '#', 1) = 'task' AND (payload #> '{diff,sys,new,joined}') IS DISTINCT FROM (payload #> '{diff,sys,old,joined}'))))"
           )

    drop_if_exists(
      index(:graph_events, ["fleet_id", "seq DESC"],
        name: "graph_events_notable_index",
        concurrently: true
      )
    )
  end

  def down do
    create index(:graph_events, ["fleet_id", "seq DESC"],
             name: "graph_events_notable_index",
             concurrently: true,
             where:
               "type = 'object.created' OR (type = 'relation.created' AND (payload #>> '{relation,type}') IN ('contradicts', 'supports', 'produces')) OR (type = 'patch.applied' AND (jsonb_exists_any(payload -> 'diff', ARRAY['status', 'progress', 'assignee_key']) OR (payload #> '{diff,sys,new,archived}') = 'true'::jsonb OR split_part(payload ->> 'target', '#', 1) IN ('goal', 'service')))"
           )

    drop_if_exists(
      index(:graph_events, ["fleet_id", "seq DESC"],
        name: "graph_events_activity_index",
        concurrently: true
      )
    )
  end
end
