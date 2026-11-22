defmodule Regents.Keyfleet.Preparations.NewestFirst do
  @moduledoc """
  Reads one of a fleet's logs newest first, from just past a place in it and
  never more than `limit` entries, whatever a caller tried to add to the query.

  `sort` names the log's order: one key, newest first (`[record_seq: :desc]`),
  a time newest first with a tie-break in ascending order
  (`[inserted_at: :desc, id: :asc]`), or a block and the log's place in it,
  both newest first (`[block_number: :desc, log_index: :desc]`). `before` names the arguments giving the
  place, one per key; an entry is read when it comes after that place in the
  order. A time with no tie-break reads the entries strictly before that
  time. With the place's arguments nil, or with no `before`, the log is read
  from its newest end.
  """
  use Ash.Resource.Preparation

  require Ash.Query

  import Ash.Expr, only: [ref: 1]

  @impl true
  def prepare(query, opts, _context) do
    sort = Keyword.fetch!(opts, :sort)
    place = Enum.map(Keyword.fetch!(opts, :before), &Ash.Query.get_argument(query, &1))

    Ash.Query.before_action(query, fn query ->
      query
      |> past(sort, place)
      |> Ash.Query.unset([:sort, :limit, :offset])
      |> Ash.Query.sort(sort)
      |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
    end)
  end

  defp past(query, _sort, []), do: query
  defp past(query, _sort, [nil | _]), do: query

  defp past(query, [{key, :desc}, _tie], [value, nil]),
    do: Ash.Query.filter(query, ^ref(key) < ^value)

  defp past(query, [{key, :desc}], [value]),
    do: Ash.Query.filter(query, ^ref(key) < ^value)

  defp past(query, [{key, :desc}, {tie, :asc}], [value, tie_value]) do
    Ash.Query.filter(
      query,
      ^ref(key) <= ^value and (^ref(key) < ^value or ^ref(tie) > ^tie_value)
    )
  end

  defp past(query, [{key, :desc}, {tie, :desc}], [value, tie_value]) do
    Ash.Query.filter(
      query,
      ^ref(key) <= ^value and (^ref(key) < ^value or ^ref(tie) < ^tie_value)
    )
  end
end
