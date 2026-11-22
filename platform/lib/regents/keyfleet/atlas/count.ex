defmodule Regents.Keyfleet.Atlas.Count do
  @moduledoc """
  Counts changes into the Atlas: each change, a touch of one thing at one
  time as one Key (or as nobody's Key), is added to that thing's row and to
  its project's and kind's bucket in every span (`Regents.Keyfleet.Atlas.Span`).

  A thing's row counts its changes and Keys and keeps its last change; a
  bucket counts the changes, the things new to it, which a row of the same
  span and start not there before says, and the Keys. Counting only ever
  adds, so a change must be counted once: the graph's changes are counted as
  far as the fleet's cursor says (`counted_seq` of `Regents.Keyfleet.Graph.Cursor`),
  by the page that copies them or by `Regents.Keyfleet.Atlas.Fill`, both holding the
  cursor, and a notebook's as `Regents.Keyfleet.Atlas.ReadHub` first sees each save,
  one fleet at a time. Graph changes and notebooks are counted into rows of
  their own kinds, so no two writers ever add to the same row at once, and a
  bucket's things are never counted twice.
  """

  alias Regents.Keyfleet.Atlas
  alias Regents.Keyfleet.Atlas.Span

  @system %Regents.Account.Actors.System{}
  @counted ~w(object.created patch.applied)

  @typedoc "One change to one thing."
  @type touch :: %{
          thing: String.t(),
          kind: String.t(),
          project: String.t(),
          at: DateTime.t(),
          key: non_neg_integer() | nil
        }

  @doc """
  The changes to items among copied graph events, as touches: an item made
  or patched, of its type (from `types`, by id, for one made before these
  events), in the project the event was placed in, at its time, as its Key.
  """
  @spec graph_touches([map()], %{String.t() => String.t()}) :: [touch()]
  def graph_touches(events, types) do
    made =
      for %{"type" => "object.created", "payload" => %{"object" => object}} <- events,
          into: types,
          do: {object["id"], object["type"]}

    for %{"type" => type} = event <- events,
        type in @counted,
        id = changed(event),
        Map.has_key?(made, id) do
      {:ok, at, _offset} = DateTime.from_iso8601(event["timestamp"])

      %{
        thing: id,
        kind: made[id],
        project: hd(event["projects"]),
        at: at,
        key: key(event["actor"])
      }
    end
  end

  defp changed(%{"type" => "object.created", "payload" => %{"object" => object}}),
    do: object["id"]

  defp changed(%{"type" => "patch.applied", "payload" => %{"patch" => patch}}),
    do: patch["target"]

  defp key(actor) do
    case Regents.Keyfleet.Graph.Event.member(actor) do
      {token_id, _kind, _wallet} -> token_id
      nil -> nil
    end
  end

  @doc """
  Counts a page of graph events the projector has just copied, in its
  transaction, with the fleet's cursor held (`cursor`), when the Atlas has
  counted the copied log as far as the page starts; it has then counted past
  the page. Otherwise it is behind, and `Regents.Keyfleet.Atlas.Fill` counts on from
  where it stopped. `objects` are the items the read tables held before the
  page, by id, each with its `type`.
  """
  @spec copied(map(), [map()], %{String.t() => map()}, non_neg_integer()) :: :ok
  def copied(%{counted_seq: seq, applied_seq: seq} = cursor, events, objects, next_seq) do
    types = Map.new(objects, fn {id, object} -> {id, object.type} end)
    count_graph(cursor.fleet_id, events, types)
    Regents.Keyfleet.Graph.mark_counted!(cursor, %{counted_seq: next_seq}, actor: @system)
    :ok
  end

  def copied(_behind, _events, _objects, _next_seq), do: :ok

  @doc "Counts graph events, of items whose types `types` holds or the events make."
  @spec count_graph(String.t(), [map()], %{String.t() => String.t()}) :: :ok
  def count_graph(fleet_id, events, types),
    do: count(fleet_id, graph_touches(events, types))

  @doc "Adds `touches` to the fleet's rows and buckets of every span."
  @spec count(String.t(), [touch()]) :: :ok
  def count(_fleet_id, []), do: :ok

  def count(fleet_id, touches) do
    grouped =
      touches
      |> Enum.flat_map(fn touch ->
        for span <- Span.all(), do: {{span, Span.start(span, touch.at), touch.thing}, touch}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    things =
      Enum.map(grouped, fn {{span, start, thing}, ts} -> row(fleet_id, span, start, thing, ts) end)

    known = known(fleet_id, things)

    buckets =
      things
      |> Enum.group_by(&{&1.span, &1.start, &1.project, &1.kind})
      |> Enum.map(fn {{span, start, project, kind}, rows} ->
        %{
          fleet_id: fleet_id,
          span: span,
          start: start,
          project: project,
          kind: kind,
          changes: Enum.sum_by(rows, & &1.changes),
          things: Enum.count(rows, &({&1.span, &1.start, &1.thing} not in known)),
          keys: rows |> Enum.flat_map(& &1.keys) |> Enum.uniq() |> Enum.sort()
        }
      end)

    written = [actor: @system, bulk_options: [return_errors?: true, stop_on_error?: true]]
    Atlas.count_things!(things, written)
    Atlas.count_buckets!(buckets, written)
    :ok
  end

  # One thing's changes in one bucket, the last of them counted last when two
  # share a time.
  defp row(fleet_id, span, start, thing, touches) do
    last = Enum.reduce(touches, &if(DateTime.compare(&1.at, &2.at) == :lt, do: &2, else: &1))
    keys = for(%{key: key} when key != nil <- touches, uniq: true, do: key) |> Enum.sort()

    %{
      fleet_id: fleet_id,
      thing: thing,
      span: span,
      start: start,
      kind: last.kind,
      project: last.project,
      changes: length(touches),
      keys: keys,
      actors: length(keys),
      last_at: last.at,
      last_key: last.key
    }
  end

  # The rows among `things` already counted in, before these are added.
  defp known(fleet_id, things) do
    ids = things |> Enum.map(& &1.thing) |> Enum.uniq()
    starts = things |> Enum.map(& &1.start) |> Enum.uniq()

    fleet_id
    |> Atlas.existing_things!(ids, starts, actor: @system)
    |> MapSet.new(&{&1.span, &1.start, &1.thing})
  end
end
