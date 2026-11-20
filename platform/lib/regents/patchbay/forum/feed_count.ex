defmodule Regents.Patchbay.Forum.FeedCount do
  @moduledoc """
  How many threads a question list (`Regents.Patchbay.Forum.Feed`) holds
  across all its pages. A count is kept on this machine for a minute under the
  list's filters but its order, which never changes the count, and shared by
  every visitor reading that list, so a busy home page counts its threads at
  most once a minute. A failed count is not kept. A list with words in it is
  not counted: its count would read the search a second time.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  alias Regents.Patchbay.Forum.Feed

  @kept :timer.minutes(1)

  @doc "The list's count as last read, read again when the kept count is more than a minute old."
  @spec count(map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(%{q: ""} = filters) do
    key = Map.delete(filters, :sort)

    case get!(key) do
      nil -> count_and_keep(key, filters)
      count -> {:ok, count}
    end
  end

  defp count_and_keep(key, filters) do
    with {:ok, count} <- filters |> Feed.query() |> Ash.Query.for_read(:feed) |> Ash.count() do
      put!(key, count, ttl: @kept)
      {:ok, count}
    end
  end
end
