defmodule Regents.Keyfleet.Preparations.SearchPage do
  @moduledoc """
  One page of a fleet's search matches of one `kind`, in the order every page
  of a search keeps (`Regents.Keyfleet.Search`): newest first, then by kind, then by
  id, whatever a caller tried to add to the query. `at` and `id` name the
  match's time and id; with `before_at` given, a match is read only when it
  comes after the place `before_at`, `before_kind` and `before_id` name in
  that order, so the place may be a match of another kind. One match more
  than `limit` is read, so the caller can tell whether more are left.
  """
  use Ash.Resource.Preparation

  require Ash.Query

  import Ash.Expr, only: [ref: 1]

  @impl true
  def prepare(query, opts, _context) do
    kind = Keyword.fetch!(opts, :kind)
    at = Keyword.fetch!(opts, :at)
    id = Keyword.fetch!(opts, :id)

    Ash.Query.before_action(query, fn query ->
      query
      |> past(at, id, kind, place(query))
      |> Ash.Query.unset([:sort, :limit, :offset])
      |> Ash.Query.sort([{at, :desc}, {id, :asc}])
      |> Ash.Query.limit(Ash.Query.get_argument(query, :limit) + 1)
    end)
  end

  defp place(query),
    do: Enum.map([:before_at, :before_kind, :before_id], &Ash.Query.get_argument(query, &1))

  defp past(query, _at, _id, _kind, [nil | _]), do: query

  # A match of a kind ordered before the place's comes after it only when it is older.
  defp past(query, at, _id, kind, [before_at, before_kind, _before_id]) when kind < before_kind,
    do: Ash.Query.filter(query, ^ref(at) < ^before_at)

  defp past(query, at, id, kind, [before_at, kind, before_id]),
    do:
      Ash.Query.filter(
        query,
        ^ref(at) < ^before_at or (^ref(at) == ^before_at and ^ref(id) > ^before_id)
      )

  defp past(query, at, _id, _kind, [before_at, _before_kind, _before_id]),
    do: Ash.Query.filter(query, ^ref(at) <= ^before_at)
end
