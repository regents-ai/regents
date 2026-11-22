defmodule Regents.Keyfleet.Rooms do
  @moduledoc """
  Fleet-scoped rooms for native chat, a public thread for every key with the
  posts its holder has taken off it, and each reader's own mutes of the keys
  whose posts they would rather not see.
  """
  use Ash.Domain

  import Ecto.Query, only: [from: 2, subquery: 1]

  require Ash.Query

  alias Regents.Account.Actors.{Agent, Human}
  alias Regents.Keyfleet.Access
  alias Regents.Keyfleet.Rooms.Errors.RoomUnknownError
  alias Regents.Keyfleet.Rooms.Muter
  alias Regents.Keyfleet.Rooms.Room

  # As many rooms as a fleet holds: six fixed rooms, five open rooms and a
  # hundred created ones.
  @max_sync_rooms 111
  # Keys' walls one catch-up follows.
  @max_sync_walls 100
  @sync_page 50
  @graph_sync_page 100
  @quotes_page 20
  # Places in a room are counted in a Postgres bigint.
  @max_seq 9_223_372_036_854_775_807
  # How far back a Key's own posts count when telling it where others have
  # posted after it.
  @posted_after_days 7
  # A Key's mentions answered at once, and how far back they are read with
  # no place to read on from.
  @mentions_page 20
  @mentions_days 7

  resources do
    resource Regents.Keyfleet.Rooms.Room do
      define :list_rooms, action: :for_fleet, args: [:fleet_id]
      define :get_room, action: :in_fleet, args: [:fleet_id, :slug], not_found_error?: false
      define :create_room, action: :create
      define :set_room_topic, action: :set_topic, args: [:topic]

      define :get_key_thread,
        action: :key_thread,
        args: [:fleet_id, :token_id],
        not_found_error?: false

      define :open_key_thread, action: :open_key_thread, args: [:fleet_id, :token_id]
      define :list_key_threads, action: :key_threads, args: [:fleet_id, :token_ids]
    end

    resource Regents.Keyfleet.Rooms.Message do
      define :send_message, action: :send_message
      define :note_room_named, action: :note_room_named
      define :read_messages, action: :read_messages, args: [:fleet_id, :slug]
      define :catch_up, action: :catch_up, args: [:fleet_id, :slugs, :after_seqs, :limit]
      define :send_to_key, action: :send_to_key
      define :read_key_thread, action: :read_key_thread, args: [:fleet_id, :token_id]

      define :catch_up_walls,
        action: :catch_up_walls,
        args: [:fleet_id, :token_ids, :after_seqs, :limit]

      define :posts_as_key, action: :posts_as_key, args: [:fleet_id, :token_id]
      define :search_posts, action: :search, args: [:fleet_id, :query]
      define :mentioning, action: :mentioning, args: [:fleet_id, :token_id]
      define :recent_posts, action: :recent_in_fleet, args: [:fleet_id]

      define :fleet_lines_before,
        action: :fleet_lines_before,
        args: [:fleet_id, :before_at, :before_id, :limit]

      define :get_post_in_room,
        action: :in_room,
        args: [:fleet_id, :id, :room_id],
        not_found_error?: false

      define :get_post_under_send_key,
        action: :under_send_key,
        args: [:fleet_id, :author_wallets, :idempotency_key],
        not_found_error?: false
    end

    resource Regents.Keyfleet.Rooms.WallRemoval do
      define :remove_from_wall, action: :remove, args: [:fleet_id, :token_id, :message_id]
    end

    resource Regents.Keyfleet.Rooms.ReadMark do
      define :mark_room_read, action: :mark, args: [:room_id, :seq]
      define :room_read_marks, action: :in_rooms, args: [:room_ids]
    end

    resource Regents.Keyfleet.Rooms.Mute do
      define :mute_key, action: :mute, args: [:fleet_id, :token_id]
      define :unmute, action: :unmute
      define :mutes_in_fleet, action: :in_fleet, args: [:fleet_id]
      define :get_mute, action: :of_key, args: [:fleet_id, :token_id], not_found_error?: false
    end

    resource Regents.Keyfleet.Rooms.QuoteRequest do
      define :ask_to_quote, action: :ask, args: [:fleet_id, :body]
      define :quote_requests_after, action: :for_agent, args: [:fleet_id, :after_seq, :limit]

      define :get_quote_request,
        action: :to_quote,
        args: [:fleet_id, :id],
        not_found_error?: false

      define :my_quote_requests, action: :mine, args: [:fleet_id]
    end
  end

  @doc """
  The wallets whose posts share one sender's send keys: a person's own
  wallets, or an agent's wallet and its person's. A send key belongs to the
  sender, not to one of its wallets, so a person's retry finds their first
  post whichever of their wallets holds the Key they write as now.
  """
  def sender_wallets(%Human{wallet_addresses: wallets}), do: wallets

  def sender_wallets(%Agent{wallet_address: wallet, pairing: %Human{wallet_addresses: person}}),
    do: [wallet | person]

  def sender_wallets(%Agent{wallet_address: wallet}), do: [wallet]

  @doc """
  Takes away `actor`'s mute of a key, if it has one: `{:ok, mute | nil}`.
  Unmuting a key that isn't muted changes nothing.
  """
  def unmute_key(fleet_id, token_id, opts) do
    case get_mute(fleet_id, token_id, opts) do
      {:ok, nil} -> {:ok, nil}
      {:ok, mute} -> with :ok <- unmute(mute, opts), do: {:ok, mute}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The keys `actor` has muted in the fleet, as a set of key numbers; none for
  anyone not signed in.
  """
  def muted_keys!(fleet_id, actor) do
    if Muter.of(actor),
      do: fleet_id |> mutes_in_fleet!(actor: actor) |> MapSet.new(& &1.token_id),
      else: MapSet.new()
  end

  @doc """
  `messages` without the posts written as a key in `muted`. How far a reader
  has got is always counted over every message, shown or not.
  """
  def unmuted(messages, muted),
    do: Enum.reject(messages, &(&1.kind == :post and MapSet.member?(muted, &1.as_key)))

  @doc """
  The fleet's rooms where others have posted since `token_id` last did, of
  the ones it posted in over the last week, as `[%{slug, after_seq, posts}]`
  by slug: `after_seq` is the place of the Key's latest post there, to read
  on from, and `posts` how many posts written as another Key, or as none,
  came after it. Muted Keys' posts are counted, as a room's places are.
  """
  def posted_after_key(fleet_id, token_id) do
    since = DateTime.add(DateTime.utc_now(), -@posted_after_days * 86_400)

    latest =
      from(m in "messages",
        prefix: ^Regents.Keyfleet.schema(),
        where:
          m.fleet_id == ^fleet_id and m.as_key == ^token_id and m.kind == "post" and
            not m.in_key_thread and m.inserted_at >= type(^since, :utc_datetime_usec),
        group_by: m.room_id,
        select: %{room_id: m.room_id, seq: max(m.seq)}
      )

    from(mine in subquery(latest),
      join: m in "messages",
      prefix: ^Regents.Keyfleet.schema(),
      on: m.room_id == mine.room_id and m.seq > mine.seq,
      join: r in "rooms",
      prefix: ^Regents.Keyfleet.schema(),
      on: r.id == mine.room_id,
      where: m.kind == "post" and (is_nil(m.as_key) or m.as_key != ^token_id),
      group_by: [r.slug, mine.seq],
      order_by: r.slug,
      select: %{slug: r.slug, after_seq: mine.seq, posts: count(m.id)}
    )
    # Asked only for a member's own Key, and a member reads every room: only
    # slugs and counts are read, over all of the Key's rooms in one query.
    |> Regents.Repo.all()
  end

  @doc """
  How many posts written as another Key, or as none, came between `message`
  and the Key's post before it in the same room or thread, as `%{after_seq,
  posts}`, `after_seq` being that earlier post's place; nil when the Key
  hadn't posted there before, or `message` was written as no Key.
  """
  def posted_after_previous(%{as_key: nil}), do: nil

  def posted_after_previous(%{room_id: room_id, as_key: key, seq: seq}) do
    in_room =
      from(m in "messages",
        prefix: ^Regents.Keyfleet.schema(),
        where: m.room_id == type(^room_id, Ecto.UUID) and m.kind == "post" and m.seq < ^seq
      )

    previous =
      from(m in in_room,
        where: m.as_key == ^key,
        order_by: [desc: m.seq],
        limit: 1,
        select: m.seq
      )

    # Asked only after `message` was posted, by its sender, who reads the room:
    # only a place and a count are read.
    case Regents.Repo.one(previous) do
      nil ->
        nil

      after_seq ->
        others =
          from(m in in_room,
            where: m.seq > ^after_seq and (is_nil(m.as_key) or m.as_key != ^key),
            select: count(m.id)
          )

        # A count in the same room, as above.
        %{after_seq: after_seq, posts: Regents.Repo.one(others)}
    end
  end

  @doc """
  Where a reader of `class` (`Regents.Keyfleet.Access.class/2`) hears what changed in
  the fleet's rooms, posts and keys' threads: "room_head", "key_activity" and
  "rooms_changed". Whoever reads every room hears of every room. Anyone else
  hears of the Public room and the keys' threads alone, and of no room made
  or named. A listener is on one of the two, never both. The Public room's
  new posts are also published whole, on `Regents.Keyfleet.Rooms.Message.topic/2`.
  """
  def topic(fleet_id, class) do
    if Access.enough?(class, :read, :rooms),
      do: "keyfleet:fleet:#{fleet_id}:rooms:members",
      else: "keyfleet:fleet:#{fleet_id}:rooms"
  end

  @doc """
  Whether posts wait after the last of `posts`, a page read with
  `read_messages` or `read_key_thread`. Nothing read means nothing waits.
  """
  def more_after?([]), do: false
  def more_after?(posts), do: posts |> List.last() |> Ash.Resource.get_metadata(:more_after)

  @doc """
  Everything one caller has not read yet across the rooms it names and the
  fleet's workspace.

  Each entry of `cursors` is a `%{slug: slug, after_seq: seq}` saying how far the
  caller has read that room. Every room the caller may read answers with the
  posts after that point, the cursor those posts reach, and the room's own
  head, so a caller that is behind knows to come back for the rest. Anyone who
  is not a member of the fleet reads the Public room alone: any other room
  they name, whether or not the fleet has it, answers with its slug alone and
  `refused: true`, and the rest of the answer stands. A caller that names
  rooms and may read none of them is refused (`Ash.Error.Forbidden`).

  `places` says how far the caller has read the rest, as
  `%{graph: seq, project: name | nil, proposals: seq, keys: walls, dms: cursors | nil, quotes: seq | nil}`.

  `graph` is the place in the workspace's log. The workspace answers with at
  most 100 of its changes after that point, the whole fleet's or, when
  `project` names one, that project's, as `Regents.Keyfleet.Graph.list_changes/3`
  does, with `next_cursor` to send next time and `run_id`: a different `run_id`
  from the one the caller last saw means the log started over, and the caller
  reads it again from 0.

  `proposals` is the place in the fleet's proposal records. Proposals answer
  with the ones changed after that point, as `Regents.Keyfleet.Proposals.changes/2`
  does.

  `keys` lists the keys' walls the caller follows, each a
  `%{token_id: key, after_seq: seq}` saying how far it has read that wall, up
  to #{@max_sync_walls} keys. Each wall answers as a room does, with
  `token_id` in place of the slug: the posts after that point, the cursor they
  reach and the wall's head. A key nobody has written to yet has a head of 0.
  Posts its holder took off the wall are never answered, and the cursor moves
  past them. A key the fleet has not issued is `KeyUnknownError`.

  `dms`, when it is not nil, maps each Key to how far its direct messages have
  been read, and they answer as `Regents.Keyfleet.Dms.changes/3` does: the messages to
  or from every Key the caller holds now, each Key after its own place. With
  nil, `dms` is nil and direct messages are not followed.

  `quotes`, when it is not nil, is the place in what the agent's person has
  asked it to quote in the fleet, which then answers as `quote_changes/3` does.
  With nil, `quotes` is nil and the requests are not followed.

  Something new, or more waiting, is answered at once, and so is everything
  when `wait?` is false. Otherwise the caller is answered as soon as the fleet
  announces a workspace change, a proposal change, a post past the caller's
  place in a room it follows, something said by or to a key whose wall it
  follows, a direct message past its Key's place or a request past its place, or after `:agent_wait_ms` with nothing, and asks again
  straight away. The announcements only say when to read again: everything
  the caller gets is read as the caller. Nothing is marked as read, and asking
  again is always safe.
  """
  def sync(fleet_id, cursors, places, actor, wait?) do
    read = fn -> read_sync(fleet_id, cursors, places, actor) end

    if wait?,
      do: wait_for_news(fleet_id, news_topics(fleet_id, places, actor), read),
      else: read.()
  end

  # What a waiting caller hears: the rooms and the workspace as its class
  # hears them, the fleet's proposals, its own inbox, and the fleet's keys,
  # since a key changing hands may change its class.
  defp news_topics(fleet_id, places, actor) do
    class = Access.class(actor, fleet_id)

    [
      topic(fleet_id, class),
      Regents.Keyfleet.Graph.topic(fleet_id, class),
      Regents.Keyfleet.Proposals.topic(fleet_id),
      Regents.Keyfleet.Keys.topic(fleet_id) | inbox_topics(fleet_id, places, actor)
    ]
  end

  defp read_sync(fleet_id, cursors, places, actor) do
    # The workspace is read first, since it answers for a fleet outside the catalog.
    with :ok <- validate_cursors(cursors),
         :ok <- validate_walls(places.keys),
         :ok <- in_log(places.graph),
         :ok <- in_log(places.proposals),
         {:ok, graph} <-
           Regents.Keyfleet.Graph.list_changes(
             fleet_id,
             %{after_seq: places.graph, project: places.project, limit: @graph_sync_page},
             actor: actor
           ),
         {:ok, rooms} <- sync_rooms(fleet_id, cursors, actor),
         {:ok, walls} <- sync_walls(fleet_id, places.keys, actor),
         {:ok, dms} <- sync_dms(fleet_id, places.dms, actor),
         {:ok, quotes} <- sync_quotes(fleet_id, places.quotes, actor) do
      proposals = Regents.Keyfleet.Proposals.changes(fleet_id, places.proposals)

      {:ok,
       %{
         rooms: rooms,
         keys: walls,
         graph: graph,
         proposals: proposals,
         dms: dms,
         quotes: quotes
       }}
    end
  end

  # Direct messages and the person's requests are followed only when asked for.
  defp sync_dms(_fleet_id, nil, _actor), do: {:ok, nil}

  defp sync_dms(fleet_id, cursors, actor),
    do: Regents.Keyfleet.Dms.changes(fleet_id, cursors, actor)

  defp sync_quotes(_fleet_id, nil, _actor), do: {:ok, nil}
  defp sync_quotes(fleet_id, after_seq, actor), do: quote_changes(fleet_id, after_seq, actor)

  defp inbox_topics(fleet_id, places, actor),
    do: dm_topics(fleet_id, places.dms, actor) ++ quote_topics(fleet_id, places.quotes, actor)

  defp dm_topics(_fleet_id, nil, _actor), do: []

  defp dm_topics(fleet_id, _cursors, actor),
    do: Regents.Keyfleet.Dms.inbox_topics(fleet_id, actor)

  defp quote_topics(fleet_id, after_seq, %Agent{human_account_id: account})
       when not is_nil(after_seq) and not is_nil(account),
       do: [Regents.Keyfleet.Rooms.QuoteRequest.topic(fleet_id, account)]

  defp quote_topics(_fleet_id, _after_seq, _actor), do: []

  @doc """
  What the agent `actor`'s person has asked it to quote in a fleet after
  `after_seq`, oldest first, at most #{@quotes_page} at a time:
  `{:ok, %{requests, next_cursor, has_more}}`. Send `next_cursor` as
  `after_seq` next time. Anyone other than a paired agent reads none.
  """
  def quote_changes(fleet_id, after_seq, actor) do
    with :ok <- in_log(after_seq),
         {:ok, requests} <-
           quote_requests_after(fleet_id, after_seq, @quotes_page + 1, actor: actor) do
      {page, more} = Enum.split(requests, @quotes_page)

      next_cursor =
        case List.last(page) do
          nil -> after_seq
          last -> last.seq
        end

      {:ok, %{requests: page, next_cursor: next_cursor, has_more: more != []}}
    end
  end

  @doc """
  The fleet's posts that mention Key `token_id`, as `actor` may read them,
  after the place `place` (`{inserted_at, id}` of the last one read, or nil
  for the last #{@mentions_days} days), oldest first and at most
  #{@mentions_page} at a time: `{:ok, %{posts, next_cursor, has_more}}`.
  Only posts written as another Key count, never as a Key `actor` muted.
  Send `next_cursor` as `place` next time; it is `place` when nothing was
  read.
  """
  def mention_changes(fleet_id, token_id, place, actor) do
    {after_at, after_id} =
      place || {DateTime.add(DateTime.utc_now(), -@mentions_days * 86_400), nil}

    args = %{
      muted: fleet_id |> muted_keys!(actor) |> MapSet.to_list(),
      after_at: after_at,
      after_id: after_id,
      limit: @mentions_page + 1
    }

    with {:ok, posts} <- mentioning(fleet_id, token_id, args, actor: actor) do
      {page, more} = Enum.split(posts, @mentions_page)

      next_cursor =
        case List.last(page) do
          nil -> place
          last -> {last.inserted_at, last.id}
        end

      {:ok, %{posts: page, next_cursor: next_cursor, has_more: more != []}}
    end
  end

  defp news?(%{rooms: rooms, keys: walls, graph: graph, proposals: proposals} = synced),
    do:
      graph.events != [] or graph.has_more or proposals.items != [] or proposals.has_more or
        Enum.any?(rooms ++ walls, &room_news?/1) or dm_news?(synced.dms) or
        quote_news?(synced.quotes)

  # A refused room answers with its slug alone, so it never brings news. A
  # wall is behind the way a room is.
  defp room_news?(%{refused: true}), do: false
  defp room_news?(room), do: room.messages != [] or room.cursor < room.head_seq

  # Direct messages and requests not asked for never bring news.
  defp dm_news?(nil), do: false
  defp dm_news?(dms), do: dms.messages != [] or dms.has_more

  defp quote_news?(nil), do: false
  defp quote_news?(quotes), do: quotes.requests != [] or quotes.has_more

  # Subscribed before the first read, so nothing announced between that read
  # and the wait is missed.
  defp wait_for_news(fleet_id, topics, read) do
    Enum.each(topics, &Phoenix.PubSub.subscribe(Regents.PubSub, &1))

    try do
      with {:ok, synced} <- read.() do
        if news?(synced),
          do: {:ok, synced},
          else:
            await_news(fleet_id, read, synced, System.monotonic_time(:millisecond) + wait_ms())
      end
    after
      Enum.each(topics, &Phoenix.PubSub.unsubscribe(Regents.PubSub, &1))
      flush_news(fleet_id)
    end
  end

  # A new run or watermark of the workspace is answered whatever it brings, as
  # the caller tells a log that started over by its `run_id`. A post is read
  # only when it is past the caller's place in a room it follows, and a direct
  # message only when it is past its Key's place; either is answered once that
  # read has something new. Anything said by or to a key whose wall the caller
  # follows is read too, since a wall nobody has written to has no place yet. Keys changing in the fleet end the wait
  # with what there is, so the caller asks again and hears what its class
  # hears now. The fleet's other announcements bring the caller nothing.
  # A steady run of other announcements must not hold the caller past its
  # deadline, so the time left is read before every wait.
  defp await_news(fleet_id, read, synced, until) do
    case until - System.monotonic_time(:millisecond) do
      left when left <= 0 ->
        {:ok, synced}

      left ->
        receive do
          {:graph_head, ^fleet_id, _run_id, _watermark} ->
            read.()

          {:graph_notable, ^fleet_id} ->
            read.()

          {:proposals_changed, ^fleet_id} ->
            read.()

          {:keys_changed, ^fleet_id, _token_ids} ->
            read.()

          %Phoenix.Socket.Broadcast{event: "room_head", payload: %{room_id: room_id, seq: seq}} ->
            if Enum.any?(
                 synced.rooms,
                 &match?(%{room_id: ^room_id, cursor: cursor} when seq > cursor, &1)
               ),
               do: read_again(fleet_id, read, until),
               else: await_news(fleet_id, read, synced, until)

          %Phoenix.Socket.Broadcast{event: "key_activity", payload: %{token_ids: token_ids}} ->
            if Enum.any?(synced.keys, &(&1.token_id in token_ids)),
              do: read_again(fleet_id, read, until),
              else: await_news(fleet_id, read, synced, until)

          %Phoenix.Socket.Broadcast{event: "dm_head", topic: topic, payload: %{seq: seq}} ->
            if seq > dm_cursor(fleet_id, synced.dms, topic),
              do: read_again(fleet_id, read, until),
              else: await_news(fleet_id, read, synced, until)

          %Phoenix.Socket.Broadcast{event: "quote_head", payload: %{seq: seq}} ->
            if match?(%{next_cursor: cursor} when seq > cursor, synced.quotes),
              do: read_again(fleet_id, read, until),
              else: await_news(fleet_id, read, synced, until)

          %Phoenix.Socket.Broadcast{} ->
            await_news(fleet_id, read, synced, until)
        after
          left -> {:ok, synced}
        end
    end
  end

  # Where the caller has read the messages of the Key whose inbox `topic` is.
  # A Key held now and not answered for is read from the start of its holding.
  defp dm_cursor(fleet_id, dms, topic) do
    Enum.find_value(dms.keys, 0, fn %{token_id: token_id, cursor: cursor} ->
      Regents.Keyfleet.Dms.inbox_topic(fleet_id, token_id) == topic and cursor
    end)
  end

  defp read_again(fleet_id, read, until) do
    case read.() do
      {:ok, again} ->
        if news?(again), do: {:ok, again}, else: await_news(fleet_id, read, again, until)

      error ->
        error
    end
  end

  # A connection kept open for the next request must not carry this wait's
  # announcements into it.
  defp flush_news(fleet_id) do
    receive do
      {:graph_head, ^fleet_id, _run_id, _watermark} -> flush_news(fleet_id)
      {:graph_notable, ^fleet_id} -> flush_news(fleet_id)
      {:proposals_changed, ^fleet_id} -> flush_news(fleet_id)
      {:keys_changed, ^fleet_id, _token_ids} -> flush_news(fleet_id)
      {:keys_present, ^fleet_id, _token_ids} -> flush_news(fleet_id)
      %Phoenix.Socket.Broadcast{} -> flush_news(fleet_id)
    after
      0 -> :ok
    end
  end

  defp wait_ms, do: Application.fetch_env!(:regents, :keyfleet_agent_wait_ms)

  # The caller's class is read once, and the rooms it is shown are the ones it
  # may read. The posts are then read before the heads. A post is only ever
  # seen once its room has counted it, so a head read afterwards is never
  # behind the posts it is returned with.
  defp sync_rooms(fleet_id, cursors, actor) do
    class = Access.class(actor, fleet_id)
    opts = [actor: actor, context: Access.context(actor, fleet_id, class)]
    rooms = Map.new(list_rooms!(fleet_id, opts), &{&1.slug, &1})
    {readable, others} = Enum.split_with(cursors, &Map.has_key?(rooms, &1.slug))

    with :ok <- known_rooms(fleet_id, others, class),
         :ok <- some_readable(readable, others),
         {:ok, posts} <- catch_up_rooms(fleet_id, readable, opts) do
      heads = Map.new(list_rooms!(fleet_id, opts), &{&1.slug, &1})
      synced = Map.new(readable, &{&1.slug, synced(&1, heads[&1.slug], posts)})

      {:ok,
       Enum.map(cursors, fn %{slug: slug} ->
         Map.get(synced, slug, %{slug: slug, refused: true})
       end)}
    end
  end

  # A member is shown every room, so one it names and is not shown is a room
  # the fleet does not have. Anyone else is shown the Public room alone, and
  # is not told which other rooms there are: those are refused, further on.
  defp known_rooms(_fleet_id, [], _class), do: :ok

  defp known_rooms(fleet_id, [%{slug: slug} | _], class) do
    if Access.enough?(class, :read, :rooms),
      do: {:error, RoomUnknownError.exception(fleet_id: fleet_id, slug: slug)},
      else: :ok
  end

  defp some_readable([], [_ | _]), do: {:error, Ash.Error.Forbidden.exception([])}
  defp some_readable(_readable, _others), do: :ok

  # The posts of every readable room named are read together, in one query,
  # and grouped by room.
  defp catch_up_rooms(_fleet_id, [], _opts), do: {:ok, %{}}

  defp catch_up_rooms(fleet_id, cursors, opts) do
    slugs = Enum.map(cursors, & &1.slug)
    after_seqs = Enum.map(cursors, & &1.after_seq)

    with {:ok, posts} <- catch_up(fleet_id, slugs, after_seqs, @sync_page, opts),
         do: {:ok, Enum.group_by(posts, & &1.room_id)}
  end

  # The posts of every wall named are read together, in one query, before the
  # walls' heads, as the rooms' are. A post taken off a wall moves the cursor
  # and is not answered.
  defp sync_walls(_fleet_id, [], _actor), do: {:ok, []}

  defp sync_walls(fleet_id, walls, actor) do
    token_ids = Enum.map(walls, & &1.token_id)
    after_seqs = Enum.map(walls, & &1.after_seq)

    with {:ok, posts} <-
           catch_up_walls(fleet_id, token_ids, after_seqs, @sync_page, actor: actor),
         {:ok, threads} <- list_key_threads(fleet_id, token_ids, actor: actor) do
      posts = Enum.group_by(posts, & &1.room_id)
      threads = Map.new(threads, &{&1.token_id, &1})
      {:ok, Enum.map(walls, &synced_wall(&1, threads[&1.token_id], posts))}
    end
  end

  defp synced_wall(%{token_id: token_id}, nil, _posts),
    do: %{token_id: token_id, head_seq: 0, cursor: 0, messages: []}

  defp synced_wall(%{token_id: token_id, after_seq: after_seq}, thread, posts) do
    read = Map.get(posts, thread.id, [])

    %{
      token_id: token_id,
      head_seq: thread.head_seq,
      cursor: cursor(read, after_seq, thread.head_seq),
      messages: Enum.reject(read, & &1.removed_from_wall)
    }
  end

  # Where reading on starts: the last post read or, with none, the after_seq
  # sent, never past the head, so an after_seq beyond it still reads the next
  # post written.
  defp cursor([], after_seq, head_seq), do: Kernel.min(after_seq, head_seq)
  defp cursor(posts, _after_seq, _head_seq), do: List.last(posts).seq

  defp synced(%{slug: slug, after_seq: after_seq}, room, posts) do
    %{id: room_id, kind: kind, head_seq: head_seq} = room
    messages = Map.get(posts, room_id, [])

    %{
      room_id: room_id,
      slug: slug,
      kind: kind,
      head_seq: head_seq,
      cursor: cursor(messages, after_seq, head_seq),
      messages: messages
    }
  end

  # One entry per room, each saying how far along that room the caller has read.
  defp validate_cursors(cursors) when is_list(cursors) do
    valid? =
      length(cursors) <= @max_sync_rooms and
        Enum.all?(cursors, fn
          %{slug: slug, after_seq: after_seq} -> is_binary(slug) and after_seq in 0..@max_seq
          _cursor -> false
        end) and
        cursors |> Enum.uniq_by(& &1.slug) |> length() == length(cursors)

    if valid?, do: :ok, else: {:error, :invalid_request}
  end

  defp validate_cursors(_cursors), do: {:error, :invalid_request}

  # One entry per wall, each saying how far along that wall the caller has read.
  defp validate_walls(walls) when is_list(walls) do
    valid? =
      length(walls) <= @max_sync_walls and
        Enum.all?(walls, fn
          %{token_id: token_id, after_seq: after_seq} ->
            token_id in 1..@max_seq and after_seq in 0..@max_seq

          _wall ->
            false
        end) and
        walls |> Enum.uniq_by(& &1.token_id) |> length() == length(walls)

    if valid?, do: :ok, else: {:error, :invalid_request}
  end

  defp validate_walls(_walls), do: {:error, :invalid_request}

  defp in_log(after_seq) when after_seq in 0..@max_seq, do: :ok
  defp in_log(_after_seq), do: {:error, :invalid_request}

  @doc """
  Names one of the fleet's open rooms, or names it again, as `actor`.

  The room takes a line saying who named it and what, and answers with its new
  topic, who set it and when. A room the fleet does not have is
  `RoomUnknownError` to a member, who is shown every room; anyone else is
  refused whichever room they name. A room that is not open is refused as
  invalid.
  """
  def name_open_room(fleet_id, slug, topic, opts) do
    case get_room(fleet_id, slug, opts) do
      {:ok, nil} -> {:error, not_shown(fleet_id, slug, opts[:actor])}
      {:ok, room} -> set_room_topic(room, topic, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp not_shown(fleet_id, slug, actor) do
    if Access.allowed?(actor, :read, :rooms, fleet_id),
      do: RoomUnknownError.exception(fleet_id: fleet_id, slug: slug),
      else: Ash.Error.Forbidden.exception([])
  end

  @doc """
  Whether `refusal` says another room of the fleet already has this `field`:
  its address (`:slug`), or the name it goes by (`:name`), which is where a
  clash is reported whether it came from naming a room or creating one.
  """
  def taken?(%Ash.Error.Invalid{errors: errors}, field),
    do: Enum.any?(errors, &taken_on?(&1, field))

  def taken?(_refusal, _field), do: false

  defp taken_on?(%Ash.Error.Changes.InvalidAttribute{field: field, private_vars: vars}, field),
    do: Keyword.get(vars || [], :constraint_type) == :unique

  # The address's lookup before the write.
  defp taken_on?(%Ash.Error.Changes.InvalidChanges{fields: fields}, field),
    do: field in (fields || [])

  defp taken_on?(_error, _field), do: false

  @doc """
  The posts written in the fleet's rooms and on its Keys' walls from `from`
  until before `to`, counted in one query (the `:written_between` read of
  messages): `posts`, how many, and `bytes`, their words as stored. Direct
  messages are not among them. Only the server counts them.
  """
  @spec posts_written(String.t(), DateTime.t(), DateTime.t()) :: %{
          posts: non_neg_integer(),
          bytes: non_neg_integer()
        }
  def posts_written(fleet_id, from, to) do
    require Ash.Expr

    system = [actor: %Regents.Account.Actors.System{}]

    Regents.Keyfleet.Rooms.Message
    |> Ash.Query.for_read(:written_between, %{fleet_id: fleet_id, from: from, to: to}, system)
    |> Ash.aggregate!(
      [
        {:posts, :count, []},
        {:bytes, :sum,
         expr: Ash.Expr.expr(fragment("octet_length(?)", body)), expr_type: :integer, default: 0}
      ],
      system
    )
  end

  @doc """
  How many posts were written in the last 24 hours in the fleet's rooms
  anyone reads, read as nobody: `{:ok, count}`, or `{:error, failure}` when
  the database doesn't answer (see `Regents.Keyfleet.Count`). Posts written to keys'
  threads are not among them.
  """
  def count_posts_last_day(fleet_id) do
    Regents.Keyfleet.Rooms.Message
    |> Ash.Query.for_read(:posts_last_day, %{fleet_id: fleet_id})
    |> Regents.Keyfleet.Count.of()
  end

  @doc "How many rooms agents have created in the fleet, counted by the server for its limit."
  def count_created_rooms!(fleet_id) do
    # The limit counts every created room, not only the ones the asker may read.
    fleet_id |> created_rooms() |> Ash.count!(authorize?: false)
  end

  @doc """
  How many of the fleet's created rooms an agent's `wallet` created, or any
  agent of its `person` (their Privy user, nil for none), counted by the
  server for its limit.
  """
  def count_rooms_created_by!(fleet_id, wallet, nil) do
    fleet_id
    |> created_rooms()
    |> Ash.Query.filter(acting_agent_wallet == ^wallet)
    # The limit counts every room they created, not only the ones they may read.
    |> Ash.count!(authorize?: false)
  end

  def count_rooms_created_by!(fleet_id, wallet, person) do
    fleet_id
    |> created_rooms()
    |> Ash.Query.filter(acting_agent_wallet == ^wallet or beneficiary_privy_user_id == ^person)
    # The limit counts every room they created, not only the ones they may read.
    |> Ash.count!(authorize?: false)
  end

  # The server's own counts for its limits: every created room, not only the
  # ones the asker may read.
  defp created_rooms(fleet_id) do
    Room
    |> Ash.Query.for_read(:for_fleet, %{fleet_id: fleet_id})
    |> Ash.Query.filter(kind == :created)
  end

  @doc """
  Ensures the six fixed rooms and the five open rooms of each fleet in
  `fleet_ids` from trusted setup code. The fleets must already be seeded.

  Reruns preserve room identities, restore canonical names and leave every open
  room's topic as members named it. The whole bootstrap commits together. This
  internal entry point must never be exposed as a user action.
  """
  def bootstrap_rooms!(fleet_ids) do
    inputs =
      for fleet_id <- fleet_ids, {slug, name, kind} <- Room.own_rooms() do
        %{fleet_id: fleet_id, slug: slug, name: name, kind: kind}
      end

    %Ash.BulkResult{records: rooms} =
      Ash.bulk_create!(inputs, Room, :bootstrap,
        actor: %Regents.Account.Actors.System{},
        return_records?: true,
        return_errors?: true,
        stop_on_error?: true,
        transaction: :all,
        sorted?: true
      )

    rooms
  end
end
