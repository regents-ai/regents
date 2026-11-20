defmodule Regents.Patchbay.Forum.SearchWords do
  @moduledoc """
  The threads a search's words find, read from indexes rather than every
  post: the questions list with words in it (`Regents.Patchbay.Forum.Report`'s
  `:feed`, `Regents.Patchbay.Forum.Feed`).

  A thread is found by its own words, its title spelled a little wrong (when
  one word is typed) or an exact tool name; by its site's address or name; by
  its own words and its site's together, each holding some of the words typed;
  by a published reply's words and fix; or by a published card. Each place's
  words (`search_vector`) are written exactly as the index built for them, and
  the words typed are read as quoted words
  (`Regents.Patchbay.Forum.SearchTerms`). PostgreSQL cannot use an index for
  each place when they are joined by "or", even within one table (a common
  word then reads every thread and rebuilds its words), so each is its own
  query, each reading its index, and the search keeps the threads any of them
  found.
  """

  require Ash.Query

  import Ecto.Query, only: [exclude: 2, select: 3, union: 2, where: 3]

  alias Regents.Patchbay.Forum.Report

  @doc "Narrows a questions list to the threads its words find, in its own order; no words, no change."
  def narrow(%Ash.Query{arguments: %{term: term}}, query) when is_binary(term) do
    with {:ok, found} <- found(term), do: {:ok, where(query, [t], t.id in subquery(found))}
  end

  def narrow(_ash_query, query), do: {:ok, query}

  defp found(term) do
    [
      Ash.Query.filter(Report, fragment("? @@ ?", search_vector, search_terms(^term, :all))),
      Ash.Query.filter(Report, fragment("? @> ARRAY[?]::text[]", tool_names, ^term)),
      # Asked as "its site matches" rather than through the site joined in: a
      # joined site may be missing, and a missing site's words read as empty
      # rather than nothing, so PostgreSQL would read every thread to check.
      Ash.Query.filter(
        Report,
        exists(
          site,
          origin == ^term or fragment("? @@ ?", search_vector, search_terms(^term, :all))
        )
      ),
      # Some words in the thread and the rest in its site's address or name:
      # each holds one word at least, which both indexes answer, and together
      # they hold every word.
      Ash.Query.filter(
        Report,
        fragment("? @@ ?", search_vector, search_terms(^term, :any)) and
          fragment("? @@ ?", site.search_vector, search_terms(^term, :any)) and
          fragment(
            "(? || ?) @@ ?",
            search_vector,
            site.search_vector,
            search_terms(^term, :all)
          )
      ),
      Ash.Query.filter(
        Report,
        exists(
          replies,
          visibility == :published and
            fragment("? @@ ?", search_vector, search_terms(^term, :all))
        )
      ),
      Ash.Query.filter(
        Report,
        exists(
          solution_cards,
          fragment("? @@ ?", search_vector, search_terms(^term, :all))
        )
      )
    ]
    |> Enum.concat(misspelt_title(term))
    |> Enum.reduce_while({:ok, nil}, fn ash_query, {:ok, found} ->
      case ids(ash_query, :id) do
        {:ok, ids} -> {:cont, {:ok, either(found, ids)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # A title spelled a little wrong, only when one word is typed. The match
  # scores a title's closest stretch against all the words typed, so a real
  # word beside a short or unknown one ("checkout x", "checkout zzzzqq")
  # scores near the real word alone and finds every thread whose title holds
  # it. A word here is what pg_trgm reads as one: a run of letters and digits.
  defp misspelt_title(term) do
    case Regex.scan(~r/[[:alnum:]]+/u, term) do
      [_one] -> [Ash.Query.filter(Report, fragment("? OPERATOR(public.<%) ?", ^term, title))]
      _words -> []
    end
  end

  defp either(nil, ids), do: ids
  defp either(found, ids), do: union(found, ^ids)

  defp ids(ash_query, field) do
    case Ash.Query.data_layer_query(ash_query) do
      {:ok, query} -> {:ok, query |> exclude(:select) |> select([row], field(row, ^field))}
      {:error, error} -> {:error, error}
    end
  end
end
