defmodule Regents.Keyfleet.Dms.Preparations.InOrder do
  @moduledoc """
  Reads direct messages oldest first and never more than the reader asked for
  (`limit`), whatever a caller tried to add to the query.

  One message more than asked for is read, and left out, so each message
  answered carries `more_after` in its metadata: whether another waits after
  it. `Regents.Keyfleet.Dms.more_after?/1` reads it from the last message answered.
  """
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    query
    |> Ash.Query.before_action(fn query ->
      query
      |> Ash.Query.unset([:sort, :limit, :offset])
      |> Ash.Query.sort(seq: :asc)
      |> Ash.Query.limit(Ash.Query.get_argument(query, :limit) + 1)
    end)
    |> Ash.Query.after_action(fn query, messages ->
      {page, rest} = Enum.split(messages, Ash.Query.get_argument(query, :limit))
      last = length(page) - 1

      {:ok,
       page
       |> Enum.with_index()
       |> Enum.map(fn {message, i} ->
         Ash.Resource.put_metadata(message, :more_after, i < last or rest != [])
       end)}
    end)
  end
end
