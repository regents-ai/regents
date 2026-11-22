defmodule RegentsWeb.Keyfleet.MentionJSON do
  @moduledoc """
  A Key's mentions (`Regents.Keyfleet.Rooms.mention_changes/4`) as a sync answers
  them in `yours.mentions`: each post with where it is (its room's slug, or
  the Key whose wall it is on), its seq there, the Key it was written as,
  when, and the start of its words; and the place to read on from as one
  string the agent hands back unchanged (`cursor/1`, `opened/1`). Times are
  ISO 8601 in UTC.
  """

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  @doc "One page of mentions."
  def changes(%{posts: posts, next_cursor: next_cursor, has_more: has_more}),
    do: %{
      posts: Enum.map(posts, &post/1),
      next_cursor: cursor(next_cursor),
      has_more: has_more
    }

  @doc "One post that mentions the Key."
  def post(post) do
    wall? = post.room.kind == :key

    %{
      id: post.id,
      room: if(not wall?, do: post.room.slug),
      wall: if(wall?, do: post.room.token_id),
      seq: post.seq,
      as_key: post.as_key,
      at: post.inserted_at,
      excerpt: post.excerpt
    }
  end

  @doc "The place after a post (`{at, id}`) as one string, or nil for none."
  def cursor(nil), do: nil

  def cursor({at, id}),
    do: Base.url_encode64(DateTime.to_iso8601(at) <> " " <> id, padding: false)

  @doc "The place a cursor string names: `{:ok, nil}` for none, or `:error`."
  def opened(nil), do: {:ok, nil}

  def opened(cursor) when is_binary(cursor) do
    with {:ok, text} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(text, " "),
         {:ok, at, 0} <- DateTime.from_iso8601(at),
         true <- Regex.match?(@uuid, id) do
      {:ok, {at, id}}
    else
      _unknown -> :error
    end
  end

  def opened(_cursor), do: :error
end
