defmodule Regents.Keyfleet.Atlas.Swarm do
  @moduledoc """
  Answers `Regents.Keyfleet.Atlas.Thing`'s `swarm` from the buckets
  (`Regents.Keyfleet.Atlas.Bucket`): the buckets of `span` that start from `from` up
  to `to`, of `source` and `project` when given, each summed over what `by`
  leaves out, oldest first. Each answer is a map of `at` (the bucket's
  start), `project` and `kind` (nil when `by` leaves it out), `changes`,
  `things` and `actors`.

  Changes and things add up across projects and kinds, as each thing is of
  one project and one kind. Keys do not: one Key at work in two projects is
  one Key across them, so `actors` counts the distinct Keys of the rows
  summed. One statement reads it all, through the buckets' primary key.
  """

  import Ecto.Query

  alias Regents.Keyfleet.Atlas.Source

  @doc "The swarm's answer to the action's arguments, as `{:ok, cells}`."
  def run(arguments) do
    %{fleet_id: fleet_id, span: span, from: from, to: to, by: by} = arguments
    group = [:start | Enum.uniq(by)]

    rows =
      from(b in "atlas_buckets",
        prefix: ^Regents.Keyfleet.schema(),
        where:
          b.fleet_id == ^fleet_id and b.span == ^Atom.to_string(span) and
            b.start >= type(^from, :utc_datetime) and b.start < type(^to, :utc_datetime),
        select: %{
          start: b.start,
          project: b.project,
          kind: b.kind,
          changes: b.changes,
          things: b.things,
          keys: b.keys
        }
      )
      |> source(arguments[:source])
      |> project(arguments[:project])

    totals =
      from(b in subquery(rows),
        group_by: ^group,
        select: ^Map.new(group, &{&1, dynamic([b], field(b, ^&1))}),
        select_merge: %{changes: sum(b.changes), things: sum(b.things)}
      )

    actors =
      from(b in subquery(rows),
        cross_lateral_join: k in fragment("SELECT unnest(?) AS key", b.keys),
        group_by: ^group,
        select: ^Map.new(group, &{&1, dynamic([b], field(b, ^&1))}),
        select_merge: %{actors: count(k.key, :distinct)}
      )

    joined =
      Enum.reduce(group, dynamic(true), fn field, on ->
        dynamic([t, a], ^on and field(t, ^field) == field(a, ^field))
      end)

    # Sums over buckets, with each Key counted once across the rows summed, are
    # no record Ash could read, so this action's answer is one statement of its own.
    cells =
      from(t in subquery(totals),
        left_join: a in subquery(actors),
        on: ^joined,
        order_by: [asc: t.start],
        select: %{
          at: t.start,
          changes: type(t.changes, :integer),
          things: type(t.things, :integer),
          actors: coalesce(a.actors, 0)
        },
        select_merge: ^Map.new(by, &{&1, dynamic([t], field(t, ^&1))})
      )
      |> Regents.Repo.all()

    {:ok,
     Enum.map(cells, fn cell ->
       cell
       |> Map.put_new(:project, nil)
       |> Map.put_new(:kind, nil)
       |> Map.update!(:at, &DateTime.from_naive!(&1, "Etc/UTC"))
     end)}
  end

  defp source(query, nil), do: query

  defp source(query, :graph),
    do: where(query, [b], b.kind != ^Source.notebook_kind())

  defp source(query, :notebook),
    do: where(query, [b], b.kind == ^Source.notebook_kind())

  defp project(query, nil), do: query
  defp project(query, project), do: where(query, [b], b.project == ^project)
end
