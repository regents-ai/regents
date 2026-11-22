defmodule Regents.Keyfleet.Rooms.Message do
  @moduledoc """
  One line in one room, in the place that room gave it: a post a member wrote,
  or the note that a member named the room. A key's thread is a room too, so a
  post written to a key is a line in its thread.

  A line is written as a key: the key the author writes as in the fleet at
  the time (`Regents.Keyfleet.Keys.identity/2`), kept as `as_key`. Lines written in
  the People and agents room (`Regents.Keyfleet.Rooms.Room.people_slug/0`) before
  posting there needed a key have no `as_key`, and keep none.

  An agent may quote its person: the post then names the person's request
  (`Regents.Keyfleet.Rooms.QuoteRequest`) and repeats their words exactly.

  Posts are never edited and never removed, so the table is the room's whole
  history and the place a post holds is the only thing a reader has to remember
  to carry on where it left off.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Keyfleet.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @bigint 9_223_372_036_854_775_807
  @max_body 4_000
  @max_page 200
  @max_posts_as_key 20
  @max_recent_in_fleet 100

  postgres do
    table "messages"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(inserted_at: "fragment(\"(clock_timestamp() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:seq, "messages_positive_seq", check: "seq > 0")

      # A post, or the line saying a member named the room.
      check_constraint(:kind, "messages_kind", check: "kind IN ('post', 'room_named')")

      check_constraint(:author_wallet, "messages_author_wallet_shape",
        check: "author_wallet ~ '^0x[0-9a-f]{40}$'"
      )

      check_constraint(:body, "messages_body_length",
        check: "length(body) BETWEEN 1 AND #{@max_body}"
      )

      # The key a line was written as, when it was written as one.
      check_constraint(:as_key, "messages_as_key", check: "as_key IS NULL OR as_key > 0")
    end

    custom_indexes do
      # A key's newest posts in the fleet's rooms.
      index(["fleet_id", "as_key", "inserted_at DESC"],
        name: "messages_posts_as_key_index",
        where: "kind = 'post' AND NOT in_key_thread"
      )

      # The fleet's newest lines across its rooms, without keys' threads.
      index(["fleet_id", "inserted_at DESC", "id"],
        name: "messages_fleet_lines_index",
        where: "NOT in_key_thread"
      )

      # One room's newest lines, without keys' threads: what the fleet's
      # lines are to anyone without one of its keys, who reads only the Public room.
      index(["fleet_id", "room_id", "inserted_at DESC", "id"],
        name: "messages_fleet_room_lines_index",
        where: "NOT in_key_thread"
      )

      # The words of the posts, as a search matches them (`:search`).
      index(["to_tsvector('english', body)"],
        name: "messages_search_index",
        using: "gin",
        where: "kind = 'post'",
        concurrently: true
      )

      # The posts that mention a Key (`:mentioning`).
      index(["mentions"],
        name: "messages_mentions_index",
        using: "gin",
        concurrently: true
      )

      # The fleet's posts in its rooms and on its Keys' walls by when they
      # were written, counted month by month (`:written_between`).
      index(["fleet_id", "inserted_at"],
        name: "messages_posts_written_index",
        where: "kind = 'post'",
        concurrently: true
      )

      # Each room's naming lines, counted to tell its posts from its lines.
      index(["room_id"], name: "messages_room_namings_index", where: "kind = 'room_named'")

      # What people have posted as each key lately, counted against their
      # hourly limit (`Regents.Keyfleet.Rooms.Changes.LimitPosts`).
      index(["fleet_id", "as_key", "inserted_at DESC"],
        name: "messages_page_posts_index",
        where: "kind = 'post' AND author_kind = 'human' AND via_agent_profile_id IS NULL"
      )
    end

    custom_statements do
      statement :immutable_messages_function do
        up("""
        CREATE FUNCTION keyfleet_app.protect_message() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
            RAISE EXCEPTION 'messages cannot be deleted' USING ERRCODE = '23514';
          END IF;
          RAISE EXCEPTION 'messages cannot be edited' USING ERRCODE = '23514';
        END;
        $$;
        """)

        down("DROP FUNCTION keyfleet_app.protect_message();")
      end

      statement :immutable_messages_trigger do
        up("""
        CREATE TRIGGER immutable_messages BEFORE UPDATE OR DELETE ON keyfleet_app.messages
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.protect_message();
        """)

        down("""
        DROP TRIGGER immutable_messages ON keyfleet_app.messages;
        """)
      end

      # Emptying the table is refused too; a row trigger never sees TRUNCATE.
      statement :untruncatable_messages_trigger do
        up("""
        CREATE TRIGGER untruncatable_messages BEFORE TRUNCATE ON keyfleet_app.messages
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.protect_message();
        """)

        down("""
        DROP TRIGGER untruncatable_messages ON keyfleet_app.messages;
        """)
      end
    end
  end

  actions do
    create :send_message do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept []
      transaction? true

      argument :fleet_id, :string, allow_nil?: false
      argument :slug, :string, allow_nil?: false

      argument :body, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: @max_body, trim?: false]

      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 128, trim?: false]

      argument :reply_to_id, :uuid

      # The request of the agent's person this post quotes, in their words.
      argument :quote_request_id, :uuid

      # The sender's own key settles a repeat: the database hands back the post
      # that key already made rather than taking a second place in the room.
      upsert? true
      upsert_identity :unique_send_key
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      validate Regents.Keyfleet.Rooms.Validations.QuotesItsPerson
      change {Regents.Keyfleet.Rooms.Changes.PostMessage, kind: :post, in: :room}
      change Regents.Keyfleet.Rooms.Changes.LimitPosts
      change Regents.Keyfleet.Agents.Changes.NoteContribution
    end

    # A post written to one of the fleet's keys, in that key's thread, which
    # the first post opens. Otherwise the same as posting in a room.
    create :send_to_key do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept []
      transaction? true

      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      argument :body, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: @max_body, trim?: false]

      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 128, trim?: false]

      argument :reply_to_id, :uuid

      upsert? true
      upsert_identity :unique_send_key
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      validate Regents.Keyfleet.Rooms.Validations.IssuedKey
      change {Regents.Keyfleet.Rooms.Changes.PostMessage, kind: :post, in: :key}
      change Regents.Keyfleet.Rooms.Changes.LimitPosts
      change Regents.Keyfleet.Agents.Changes.NoteContribution
    end

    # The line an open room takes when a member names it, written inside the
    # naming itself (`Regents.Keyfleet.Rooms.Changes.NameRoom`), so the room's watchers
    # hear of it once the naming commits. Its body is the room's new topic.
    create :note_room_named do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      public? false
      accept []
      transaction? true

      argument :fleet_id, :string, allow_nil?: false
      argument :slug, :string, allow_nil?: false

      argument :body, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: @max_body, trim?: false]

      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 128, trim?: false]

      change {Regents.Keyfleet.Rooms.Changes.PostMessage, kind: :room_named, in: :room}
    end

    # A room's naming lines, when a room's posts are counted.
    read :read do
      primary? true
      public? false
    end

    read :read_messages do
      argument :fleet_id, :string, allow_nil?: false
      argument :slug, :string, allow_nil?: false
      argument :after_seq, :integer, default: 0, constraints: [min: 0, max: @bigint]
      argument :limit, :integer, default: 100, constraints: [min: 1, max: @max_page]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      filter expr(seq > ^arg(:after_seq))

      prepare build(
                load: [:agent_profile, :via_agent_profile],
                deselect: [:beneficiary_privy_user_id]
              )

      prepare {Regents.Keyfleet.Rooms.Preparations.OneRoom, in: :room}
      metadata :more_after, :boolean, allow_nil?: false
    end

    # The posts after each of several of the fleet's rooms' cursors, oldest
    # first in each room and at most `limit` from each, in one query: the
    # `n`th slug is read after the `n`th place in `after_seqs`. A slug the
    # fleet has no room for reads nothing.
    read :catch_up do
      argument :fleet_id, :string, allow_nil?: false
      argument :slugs, {:array, :string}, allow_nil?: false
      argument :after_seqs, {:array, :integer}, allow_nil?: false
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: @max_page]

      filter expr(
               fragment(
                 """
                 ? IN (
                   SELECT later.id
                   FROM unnest(?::text[], ?::bigint[]) AS cursor(slug, after_seq)
                   JOIN keyfleet_app.rooms AS room
                     ON room.fleet_id = ? AND room.slug = cursor.slug AND room.kind <> 'key'
                   CROSS JOIN LATERAL (
                     SELECT message.id FROM keyfleet_app.messages AS message
                     WHERE message.room_id = room.id AND message.seq > cursor.after_seq
                     ORDER BY message.seq
                     LIMIT ?
                   ) AS later
                 )
                 """,
                 id,
                 ^arg(:slugs),
                 ^arg(:after_seqs),
                 ^arg(:fleet_id),
                 ^arg(:limit)
               )
             )

      prepare build(load: [:agent_profile, :via_agent_profile], sort: [seq: :asc])
    end

    # The posts after each of several keys' threads' cursors, oldest first in
    # each thread and at most `limit` from each, in one query: the `n`th key is
    # read after the `n`th place in `after_seqs`. A key nobody has written to
    # yet reads nothing. Posts their Key's holder took off the wall are read
    # too, marked `removed_from_wall`, so a reader's place can move past them;
    # they are never shown.
    read :catch_up_walls do
      argument :fleet_id, :string, allow_nil?: false

      argument :token_ids, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 1, max: @bigint]]

      argument :after_seqs, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 0, max: @bigint]]

      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: @max_page]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      validate {Regents.Keyfleet.Rooms.Validations.IssuedKey, argument: :token_ids}

      filter expr(
               fragment(
                 """
                 ? IN (
                   SELECT later.id
                   FROM unnest(?::bigint[], ?::bigint[]) AS cursor(token_id, after_seq)
                   JOIN keyfleet_app.rooms AS room
                     ON room.fleet_id = ? AND room.slug = 'key-' || cursor.token_id
                       AND room.kind = 'key'
                   CROSS JOIN LATERAL (
                     SELECT message.id FROM keyfleet_app.messages AS message
                     WHERE message.room_id = room.id AND message.seq > cursor.after_seq
                     ORDER BY message.seq
                     LIMIT ?
                   ) AS later
                 )
                 """,
                 id,
                 ^arg(:token_ids),
                 ^arg(:after_seqs),
                 ^arg(:fleet_id),
                 ^arg(:limit)
               )
             )

      prepare build(
                load: [:agent_profile, :via_agent_profile, :removed_from_wall],
                sort: [seq: :asc]
              )
    end

    # The posts written to one of the fleet's keys, read the way a room is.
    read :read_key_thread do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :after_seq, :integer, default: 0, constraints: [min: 0, max: @bigint]
      argument :limit, :integer, default: 100, constraints: [min: 1, max: @max_page]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      validate Regents.Keyfleet.Rooms.Validations.IssuedKey
      # A post its Key's holder took off the wall is left out for everyone.
      filter expr(seq > ^arg(:after_seq) and not exists(wall_removal, true))

      prepare build(
                load: [:agent_profile, :via_agent_profile],
                deselect: [:beneficiary_privy_user_id]
              )

      prepare {Regents.Keyfleet.Rooms.Preparations.OneRoom, in: :key}
      metadata :more_after, :boolean, allow_nil?: false
    end

    # What one key has said in the fleet's rooms, newest first. Posts written
    # to keys' threads are left out.
    read :posts_as_key do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      argument :limit, :integer,
        default: @max_posts_as_key,
        constraints: [min: 1, max: @max_posts_as_key]

      filter expr(
               kind == :post and fleet_id == ^arg(:fleet_id) and as_key == ^arg(:token_id) and
                 not in_key_thread
             )

      prepare build(
                load: [:room, :agent_profile, :via_agent_profile],
                deselect: [:beneficiary_privy_user_id]
              )

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [inserted_at: :desc, id: :asc], before: []}
    end

    # The fleet's newest posts in its rooms, newest first, for the fleet
    # directory, which keeps the newest from each writer among them. Posts
    # written to keys' threads are left out.
    read :recent_in_fleet do
      argument :fleet_id, :string, allow_nil?: false

      argument :limit, :integer,
        default: @max_recent_in_fleet,
        constraints: [min: 1, max: @max_recent_in_fleet]

      filter expr(kind == :post and fleet_id == ^arg(:fleet_id) and not in_key_thread)

      prepare build(load: [:room, :agent_profile, :via_agent_profile])

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [inserted_at: :desc, id: :asc], before: []}
    end

    # The posts written in the fleet's rooms in the last 24 hours, for
    # counting them in the fleet directory. Posts written to keys' threads
    # are left out. Read through the fleet's room lines index
    # (`messages_fleet_room_lines_index`).
    read :posts_last_day do
      argument :fleet_id, :string, allow_nil?: false

      filter expr(
               kind == :post and fleet_id == ^arg(:fleet_id) and not in_key_thread and
                 inserted_at > ago(1, :day)
             )
    end

    # The fleet's lines in its rooms older than one line, newest first, for
    # the fleet's activity: posts and namings, without the posts written to
    # keys' threads. Ties in time come in id order. Each line comes with its
    # room and author but only the start of its words. It reads the fleet's
    # lines index (`messages_fleet_lines_index`) from the given line down, or
    # the Public room's (`messages_fleet_room_lines_index`) for anyone without a key.
    # `keys` and `wallet` keep the lines written as those Keys, or by that
    # wallet or by an agent with it (`Regents.Keyfleet.Preparations.DoneBy`).
    read :fleet_lines_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_at, :utc_datetime_usec
      argument :before_id, :uuid
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: @max_page]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

      filter expr(fleet_id == ^arg(:fleet_id) and not in_key_thread)

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [inserted_at: :desc, id: :asc], before: [:before_at, :before_id]}

      prepare {Regents.Keyfleet.Preparations.DoneBy,
               key: :as_key, wallet: [:author_wallet, :acting_agent_wallet]}

      prepare build(
                select: [
                  :id,
                  :fleet_id,
                  :room_id,
                  :seq,
                  :kind,
                  :author_kind,
                  :author_wallet,
                  :as_key,
                  :agent_profile_id,
                  :via_agent_profile_id,
                  :inserted_at
                ],
                load: [:excerpt, :room, :agent_profile, :via_agent_profile]
              )
    end

    # Every post one key has written in the fleet's rooms, for counting them.
    read :room_posts_as_key do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      filter expr(
               kind == :post and fleet_id == ^arg(:fleet_id) and as_key == ^arg(:token_id) and
                 not in_key_thread
             )
    end

    # Every post one person's wallet has written in the fleet's rooms, for
    # counting them.
    read :room_posts_by_wallet do
      argument :fleet_id, :string, allow_nil?: false
      argument :wallet, :string, allow_nil?: false

      filter expr(
               kind == :post and author_kind == :human and fleet_id == ^arg(:fleet_id) and
                 author_wallet == ^arg(:wallet) and not in_key_thread
             )
    end

    # What people have posted themselves as one key in the last hour, in the
    # fleet's rooms and keys' threads together, newest first: the posts an
    # agent writes, for itself or for its person, are not among them.
    read :page_posts_last_hour do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      filter expr(
               kind == :post and fleet_id == ^arg(:fleet_id) and as_key == ^arg(:token_id) and
                 author_kind == :human and is_nil(via_agent_profile_id) and
                 inserted_at > ago(1, :hour)
             )

      prepare build(sort: [inserted_at: :desc, id: :asc])
    end

    # The posts written in the fleet's rooms and on its Keys' walls from
    # `from` until before `to`, for counting a month's chat
    # (`Regents.Keyfleet.Rooms.posts_written/3`). The lines naming a room are not
    # posts. Read through `messages_posts_written_index`.
    read :written_between do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :to, :utc_datetime_usec, allow_nil?: false

      filter expr(
               kind == :post and fleet_id == ^arg(:fleet_id) and inserted_at >= ^arg(:from) and
                 inserted_at < ^arg(:to)
             )
    end

    read :in_room do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      argument :room_id, :uuid, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and id == ^arg(:id) and room_id == ^arg(:room_id))
      get? true
    end

    # The first post a sender made under a send key from any of its wallets, so
    # a person's retry is known whichever of their wallets now holds the key
    # they write as.
    read :under_send_key do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :author_wallets, {:array, :string}, allow_nil?: false
      argument :idempotency_key, :string, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and author_wallet in ^arg(:author_wallets) and
                 idempotency_key == ^arg(:idempotency_key)
             )

      prepare build(sort: [inserted_at: :asc, id: :asc], limit: 1)
      get? true
    end

    # The fleet's posts whose words match a search, in its rooms and on its
    # Keys' walls, a page at a time (`Regents.Keyfleet.Search`). A post its Key's
    # holder took off the wall is left out, and so are posts written as a Key
    # in `muted`. Words are matched as English, through the posts' search
    # index (`messages_search_index`).
    read :search do
      argument :fleet_id, :string, allow_nil?: false
      argument :query, :string, allow_nil?: false, constraints: [max_length: 200, trim?: false]
      argument :muted, {:array, :integer}, allow_nil?: false, default: []
      argument :before_at, :utc_datetime_usec
      argument :before_kind, :string
      argument :before_id, :string
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: @max_page]

      filter expr(
               fleet_id == ^arg(:fleet_id) and kind == :post and
                 not exists(wall_removal, true) and
                 (is_nil(as_key) or as_key not in ^arg(:muted)) and
                 fragment(
                   "to_tsvector('english', ?) @@ websearch_to_tsquery('english', ?)",
                   body,
                   ^arg(:query)
                 )
             )

      prepare build(
                load: [:room, :agent_profile, :via_agent_profile, match: [query: arg(:query)]],
                deselect: [:beneficiary_privy_user_id]
              )

      prepare {Regents.Keyfleet.Preparations.SearchPage, kind: "post", at: :inserted_at, id: :id}
    end

    # The fleet's posts that mention Key `token_id`, in its rooms and on its
    # Keys' walls, oldest first from just past a place: written at `after_at`
    # with an id past `after_id`, or after `after_at` when `after_id` is nil.
    # Only posts written as another Key count, not as `token_id` itself, as
    # none, or as a Key in `muted`; a post its Key's holder took off the wall
    # is left out. Read through the mentions index (`messages_mentions_index`).
    read :mentioning do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :muted, {:array, :integer}, allow_nil?: false, default: []
      argument :after_at, :utc_datetime_usec, allow_nil?: false
      argument :after_id, :uuid
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: @max_page]

      filter expr(
               fleet_id == ^arg(:fleet_id) and kind == :post and
                 fragment("? @> ARRAY[?]::bigint[]", mentions, ^arg(:token_id)) and
                 not is_nil(as_key) and as_key != ^arg(:token_id) and
                 as_key not in ^arg(:muted) and not exists(wall_removal, true) and
                 (inserted_at > ^arg(:after_at) or
                    (inserted_at == ^arg(:after_at) and not is_nil(^arg(:after_id)) and
                       id > ^arg(:after_id)))
             )

      prepare build(
                load: [:room, :excerpt],
                sort: [inserted_at: :asc, id: :asc],
                limit: arg(:limit)
              )
    end
  end

  # Delivered after the transaction commits, as `%Phoenix.Socket.Broadcast{}`.
  #
  # A post in a room anyone reads (`Regents.Keyfleet.Rooms.Room.read_by_anyone/0`) goes
  # first, whole, on that room's own topic (`topic/2`): "post" with `public/2`,
  # what a signed-out reader of the room is shown of it, so every open page of
  # the room shows it without reading the room. Its order marker is `seq`, the
  # place the database gave it under the room's lock (`Regents.Keyfleet.Rooms.Sequence`).
  # Those rooms are read by anyone (`Regents.Keyfleet.Access`, `:general_room` and
  # `:people_room` read `:public`, checked for posts by
  # `Regents.Keyfleet.Rooms.Checks.RoomsAnyoneReads`); if that read ever narrows, this
  # publication goes in the same change, since the policy does not guard it.
  #
  # Then, on the two topics of `Regents.Keyfleet.Rooms.topic/2`: "room_head" with
  # `%{room_id, seq}` for every new line, and "key_activity" with
  # `%{fleet_id, token_ids}` for a new post, naming the key it was written as
  # and the key whose thread it went to. The members' topic takes every line.
  # The other takes a line of a room anyone reads or of a key's thread, and
  # nothing of any other room.
  #
  # Publications are sent in the order written here, from the one process
  # that posted, so a page of such a room hears a post before the room's head
  # that counts it: a page that showed the post is level with the head and
  # does nothing more, and a page that missed it reads the room from the head.
  # A repeat the database handed back is not announced. Best effort: a page
  # that hears nothing reads the room when it is next opened.
  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet"
    broadcast_type :phoenix_broadcast
    filter &(!Ash.Resource.get_metadata(&1.data, :upsert_skipped))

    publish :send_message, ["public", "room", :fleet_id, :room_id],
      event: "post",
      filter: &Regents.Keyfleet.Rooms.Message.in_room_anyone_reads?/1,
      load: [:reply_to_seq, :agent_profile, :via_agent_profile],
      returns: :map,
      transform:
        &Regents.Keyfleet.Rooms.Message.public(
          &1.data,
          Map.get(&1.data.calculations, :reply_to_seq)
        )

    publish_all :create, ["fleet", :fleet_id, "rooms", "members"],
      event: "room_head",
      transform: &Regents.Keyfleet.Rooms.Message.head/1

    publish_all :create, ["fleet", :fleet_id, "rooms"],
      event: "room_head",
      transform: &Regents.Keyfleet.Rooms.Message.head/1,
      filter: &Regents.Keyfleet.Rooms.Message.read_by_anyone?/1

    publish :send_message, ["fleet", :fleet_id, "rooms", "members"],
      event: "key_activity",
      transform: &Regents.Keyfleet.Rooms.Message.key_activity/1

    publish :send_message, ["fleet", :fleet_id, "rooms"],
      event: "key_activity",
      transform: &Regents.Keyfleet.Rooms.Message.key_activity/1,
      filter: &Regents.Keyfleet.Rooms.Message.read_by_anyone?/1

    publish :send_to_key, ["fleet", :fleet_id, "rooms", "members"],
      event: "key_activity",
      transform: &Regents.Keyfleet.Rooms.Message.key_activity/1

    publish :send_to_key, ["fleet", :fleet_id, "rooms"],
      event: "key_activity",
      transform: &Regents.Keyfleet.Rooms.Message.key_activity/1
  end

  @doc """
  The topic on which each new post of the fleet's room `room_id` is published
  whole, when anyone may read that room: the Public room and the People and
  agents room.
  """
  def topic(fleet_id, room_id), do: "keyfleet:public:room:#{fleet_id}:#{room_id}"

  @doc """
  What anyone is shown of a line, named one by one: what a room's page draws
  of it, and what the topic of a room anyone reads carries for each new post
  (`topic/2`). `as_key` is nil for a line written as no key.
  `reply_to_seq` is the place of the post it answers, nil when it answers
  none: a calculation, on the line when the page reads it with
  `load: [:reply_to_seq]` and from the publication's own load when it is
  published. Who wrote it is `author/1`.
  """
  def public(message, reply_to_seq) do
    %{
      id: message.id,
      room_id: message.room_id,
      seq: message.seq,
      kind: message.kind,
      as_key: message.as_key,
      body: message.body,
      inserted_at: message.inserted_at,
      reply_to_seq: message.reply_to_id && reply_to_seq,
      quoting?: message.quote_request_id != nil,
      author: author(message)
    }
  end

  @doc """
  Who wrote a line, as anyone is shown it: an agent by its name, what it runs
  on, its picture and whether a verified person stands behind it; a person by
  their wallet and the name of the agent that wrote it for them. `arrival` is how it reached Keyfleet: `:agent` when an agent's
  signed request carried it, as the agent itself or for its person, and
  `:web` when a person typed it on the website. Needs the line's
  `agent_profile` and `via_agent_profile`.
  """
  def author(%{author_kind: :agent, agent_profile: %{name: name} = profile}),
    do: %{
      kind: :agent,
      arrival: :agent,
      name: name,
      harness: profile.declared_harness,
      picture: picture(profile.avatar_src),
      human_backed: profile.human_backed == true,
      wallet: nil,
      via_agent: nil
    }

  def author(message),
    do: %{
      kind: :human,
      arrival:
        if(message.author_kind == :agent or message.via_agent_profile_id != nil,
          do: :agent,
          else: :web
        ),
      name: nil,
      harness: nil,
      picture: nil,
      human_backed: false,
      wallet: message.author_wallet,
      via_agent: via_agent(message.via_agent_profile)
    }

  # A picture not read with the profile is not shown.
  defp picture(src) when is_binary(src), do: src
  defp picture(_not_read), do: nil

  defp via_agent(%{name: name}), do: name
  defp via_agent(_none), do: nil

  @doc false
  def head(%{data: message}), do: %{room_id: message.room_id, seq: message.seq}

  # A post written to one of the rooms anyone reads.
  @doc false
  def in_room_anyone_reads?(%{changeset: changeset}),
    do:
      Map.has_key?(
        Regents.Keyfleet.Rooms.Room.read_by_anyone(),
        Ash.Changeset.get_argument(changeset, :slug)
      )

  # A line of a key's thread, or one written to a room anyone reads.
  @doc false
  def read_by_anyone?(%{data: message} = notification),
    do: message.in_key_thread or in_room_anyone_reads?(notification)

  @doc false
  def key_activity(%{data: message, changeset: changeset}) do
    token_ids = Enum.uniq([message.as_key, Ash.Changeset.get_argument(changeset, :token_id)])
    %{fleet_id: message.fleet_id, token_ids: Enum.reject(token_ids, &is_nil/1)}
  end

  policies do
    # Spec section 7, by the classes of `Regents.Keyfleet.Access`: the fleet's members
    # read every room and thread of it, and anyone else only the rooms anyone
    # reads and the keys' threads. Posting is for members alone, and in the rooms
    # for their agents alone: people write on keys' threads, and in the People
    # and agents room.
    policy action([:read_key_thread, :catch_up_walls]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :key_walls, scope: :fleet_id}
    end

    # A room only members read is refused to anyone else, never read as empty;
    # so is a catch-up across rooms that names one.
    policy action([:read_messages, :catch_up]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :rooms, scope: :fleet_id}
      authorize_if Regents.Keyfleet.Rooms.Checks.RoomsAnyoneReads
    end

    # The reads across the fleet's rooms, which leave the keys' threads out,
    # show anyone else only the rooms anyone reads.
    policy action([
             :read,
             :posts_as_key,
             :recent_in_fleet,
             :posts_last_day,
             :fleet_lines_before,
             :room_posts_as_key,
             :room_posts_by_wallet,
             :in_room,
             :under_send_key
           ]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :rooms, scope: :fleet_id}
      authorize_if Regents.Keyfleet.Rooms.Checks.InRoomsAnyoneReads
    end

    # A search and a Key's mentions read, of the posts anyone else may read,
    # only those in the rooms anyone reads and on the Keys' walls.
    policy action([:search, :mentioning]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :rooms, scope: :fleet_id}
      authorize_if {Regents.Keyfleet.Rooms.Checks.InRoomsAnyoneReads, walls: true}
    end

    policy action(:send_message) do
      authorize_if Regents.Keyfleet.Rooms.Checks.PeopleRoomWriter
      forbid_unless actor_attribute_equals(:role, :agent)
      authorize_if {Regents.Keyfleet.Access.Check, write: :rooms, scope: :fleet_id}
    end

    policy action(:note_room_named) do
      forbid_unless actor_attribute_equals(:role, :agent)
      authorize_if {Regents.Keyfleet.Access.Check, write: :rooms, scope: :fleet_id}
    end

    policy action(:send_to_key) do
      authorize_if {Regents.Keyfleet.Access.Check, write: :key_walls, scope: :fleet_id}
    end

    # The hourly count behind a person's posting limit is the server's own read.
    policy action(:page_posts_last_hour) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    # So is the month's count of the fleet's chat.
    policy action(:written_between) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    # The person an agent wrote the post for. No page shows it, so the reads
    # pages show posts from leave it out.
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    uuid_primary_key :id

    attribute :seq, :integer,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [min: 1, max: @bigint]

    # A post a member wrote, or the note that a member named the room.
    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [one_of: [:post, :room_named]]

    # Whether the line is in a key's thread rather than one of the fleet's
    # rooms, kept on the line so the fleet's room lines are read without
    # looking at their rooms.
    attribute :in_key_thread, :boolean,
      allow_nil?: false,
      public?: false,
      writable?: false

    attribute :author_kind, :atom,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [one_of: [:human, :agent]]

    attribute :author_wallet, :string,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    # The key the line was written as: the key the author wrote as in the
    # fleet then (`Regents.Keyfleet.Keys.identity/2`). Lines written as no key in the
    # People and agents room, before posting there needed a key, have none, and
    # so do lines written before keys were recorded.
    attribute :as_key, :integer,
      public?: true,
      writable?: false,
      constraints: [min: 1, max: @bigint]

    attribute :body, :string,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [min_length: 1, max_length: @max_body, trim?: false]

    # The Keys the post's words mention (`Regents.Keyfleet.Rooms.Mentions`), read from
    # them as the post is written; a naming line and posts written before
    # mentions were kept mention none.
    attribute :mentions, {:array, :integer},
      allow_nil?: false,
      default: [],
      public?: true,
      writable?: false,
      constraints: [items: [min: 1, max: @bigint], max_length: 20]

    # The same words under the same send key are the same post; different words
    # are a mistake the sender is told about instead of a second post.
    attribute :body_digest, :string,
      allow_nil?: false,
      public?: false,
      writable?: false,
      constraints: [match: ~r/\A[0-9a-f]{64}\z/, trim?: false]

    attribute :idempotency_key, :string,
      allow_nil?: false,
      public?: false,
      writable?: false,
      constraints: [min_length: 1, max_length: 128, trim?: false]

    attribute :inserted_at, :utc_datetime_usec,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      attribute_writable? false
      allow_nil? false
      public? true
    end

    belongs_to :room, Regents.Keyfleet.Rooms.Room do
      attribute_writable? false
      allow_nil? false
      public? true
    end

    belongs_to :agent_profile, Regents.Keyfleet.Agents.AgentProfile do
      attribute_writable? false
      public? true
      read_action :public_profile
    end

    # The agent that wrote a person's line for them, as the agent paired with
    # them (`Regents.Keyfleet.Keys.identity/2`); nil when the person wrote it.
    belongs_to :via_agent_profile, Regents.Keyfleet.Agents.AgentProfile do
      attribute_writable? false
      public? true
      read_action :public_profile
    end

    belongs_to :reply_to, Regents.Keyfleet.Rooms.Message do
      attribute_writable? false
      public? true
    end

    # The request of its person an agent quoted in this post; quoted once.
    belongs_to :quote_request, Regents.Keyfleet.Rooms.QuoteRequest do
      attribute_writable? false
      public? true
    end

    # Set once the holder of the Key whose wall the post is on has taken it off.
    has_one :wall_removal, Regents.Keyfleet.Rooms.WallRemoval
  end

  calculations do
    # The line's words as they start, cut in the database: a line longer than
    # 160 characters ends at its last whole word within them, with "…" in
    # place of any stop or comma after it.
    calculate :excerpt,
              :string,
              expr(
                fragment(
                  "CASE WHEN length(?) <= 160 THEN ? ELSE rtrim(left(regexp_replace(left(?, 161), '\\s+\\S*$', ''), 160), '.,;:') || '…' END",
                  body,
                  body,
                  body
                )
              ),
              public?: true

    # Whether the holder of the Key whose wall the post is on has taken it off.
    calculate :removed_from_wall, :boolean, expr(exists(wall_removal, true))

    # The words around what a search matched in the post, at most 24 of them.
    calculate :match,
              :string,
              expr(
                fragment(
                  ~S|ts_headline('english', ?, websearch_to_tsquery('english', ?), 'StartSel="", StopSel="", MaxWords=24, MinWords=8')|,
                  body,
                  ^arg(:query)
                )
              ) do
      argument :query, :string, allow_nil?: false, constraints: [trim?: false]
    end

    # The place of the post this one answers, which is always in the same room.
    calculate :reply_to_seq,
              :integer,
              expr(
                fragment(
                  "(SELECT answered.seq FROM keyfleet_app.messages AS answered WHERE answered.id = ?)",
                  reply_to_id
                )
              )
  end

  identities do
    identity :unique_place_in_room, [:room_id, :seq]
    identity :unique_send_key, [:fleet_id, :author_wallet, :idempotency_key]
    identity :one_quote_per_request, [:quote_request_id]
  end
end
