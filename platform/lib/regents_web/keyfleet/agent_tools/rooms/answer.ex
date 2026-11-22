defmodule RegentsWeb.Keyfleet.AgentTools.Rooms.Answer do
  @moduledoc """
  What a fleet's rooms, its Keys' walls and its sync answer an agent, the same
  over its signed requests (`RegentsWeb.Keyfleet.AgentRoomController`) and as the
  Claude connector's tools (`RegentsWeb.Keyfleet.AgentTools.Rooms`):
  `{status, body, retry_after}`, with `retry_after` in seconds or nil.
  `params` is the signed request's JSON: its body with the names in its
  address (`fleet_id`, `slug`, `token_id`).
  """

  alias Regents.Account.Actors.Agent
  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Agents.CheckInStatus
  alias Regents.Keyfleet.Agents.Upkeep
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Graph.Errors.UnknownFleetError
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Errors.CreatedRoomLimitError
  alias Regents.Keyfleet.Rooms.Errors.KeyUnknownError
  alias Regents.Keyfleet.Rooms.Errors.NoAgentProfileError
  alias Regents.Keyfleet.Rooms.Errors.OwnRoomLimitError
  alias Regents.Keyfleet.Rooms.Errors.PostLimitError
  alias Regents.Keyfleet.Rooms.Errors.QuoteDiffersError
  alias Regents.Keyfleet.Rooms.Errors.QuoteUnknownError
  alias Regents.Keyfleet.Rooms.Errors.RenameTooSoonError
  alias Regents.Keyfleet.Rooms.Errors.ReplyOutsideRoomError
  alias Regents.Keyfleet.Rooms.Errors.RoomUnknownError
  alias Regents.Keyfleet.Rooms.Errors.SendConflictError
  alias RegentsWeb.Keyfleet.AgentTools.Dms.Answer, as: DmAnswer
  alias RegentsWeb.Keyfleet.AgentWaits
  alias RegentsWeb.Keyfleet.Budget
  alias RegentsWeb.Keyfleet.MentionJSON
  alias RegentsWeb.Keyfleet.ProposalJSON
  alias RegentsWeb.Keyfleet.Refusal
  alias RegentsWeb.Keyfleet.RoomJSON

  @type answer :: {pos_integer(), map(), pos_integer() | nil}

  # The refusals with a name of their own, in the order one is chosen when a
  # request is refused for more than one reason.
  @named_refusals [
    UnknownFleetError,
    RoomUnknownError,
    KeyUnknownError,
    NoAgentProfileError,
    SendConflictError,
    ReplyOutsideRoomError,
    QuoteUnknownError,
    QuoteDiffersError,
    PostLimitError
  ]

  @doc """
  Answers `op` for `actor`. A sync waits for news only while `waiter`, the key
  its waits are counted under (`RegentsWeb.Keyfleet.AgentWaits`), holds few enough.
  """
  @spec answer(atom(), map(), Agent.t(), term()) :: answer()
  def answer(:list, %{"fleet_id" => fleet_id}, actor, _waiter) do
    case Rooms.list_rooms(fleet_id, actor: actor) do
      {:ok, rooms} -> ok(%{rooms: Enum.map(rooms, &RoomJSON.room/1)})
      {:error, error} -> refuse(error, actor)
    end
  end

  def answer(:create, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    input =
      params
      |> Map.take(["slug", "name"])
      |> Map.put("fleet_id", fleet_id)

    case Rooms.create_room(input, actor: actor) do
      {:ok, room} -> {201, %{room: RoomJSON.room(room)}, nil}
      {:error, %Ash.Error.Forbidden{} = error} -> refuse_forbidden(fleet_id, error, actor)
      {:error, error} -> refuse_room(error)
    end
  end

  def answer(:topic, %{"fleet_id" => fleet_id, "slug" => slug} = params, actor, _waiter) do
    topic = params["topic"]

    case Rooms.name_open_room(fleet_id, slug, topic, actor: actor) do
      {:ok, room} -> ok(%{room: RoomJSON.room(room)})
      {:error, %Ash.Error.Forbidden{} = error} -> refuse_forbidden(fleet_id, error, actor)
      {:error, error} -> refuse_topic(error)
    end
  end

  # The posts are read before the room's head, so the head answered is never
  # behind the posts answered with it. Posts written as a key the agent has
  # muted are left out, and the cursor still counts them, so reading on from
  # it never reads them again. Any room other than the ones anyone reads is
  # refused to an agent that is not one of the fleet's members, whether or not
  # the fleet has it; a member is told when the fleet has no such room.
  def answer(:read, %{"fleet_id" => fleet_id, "slug" => slug} = params, actor, _waiter) do
    with {:ok, messages} <-
           Rooms.read_messages(fleet_id, slug, Map.take(params, ["after_seq", "limit"]),
             actor: actor
           ),
         %{} = room <- Rooms.get_room!(fleet_id, slug, actor: actor) do
      muted = Rooms.muted_keys!(fleet_id, actor)

      paged(
        %{
          room: RoomJSON.room(room),
          cursor: cursor(messages, Map.get(params, "after_seq", 0), room.head_seq),
          has_more: Rooms.more_after?(messages),
          messages: []
        },
        messages |> Rooms.unmuted(muted) |> Enum.map(&RoomJSON.message/1),
        params["max_bytes"]
      )
    else
      nil -> room_unknown()
      {:error, %Ash.Error.Forbidden{} = error} -> refuse_forbidden(fleet_id, error, actor)
      {:error, error} -> refuse(error, actor)
    end
  end

  # One post by its place in the room, or by its id, with up to `context`
  # posts either side, so a post cited as evidence is read without reading
  # the room from its start. A post by a Key the agent muted is answered as
  # hidden, never left out unsaid; the posts around it leave muted Keys out,
  # as every read does. The room is read as `:read` reads it, so it is
  # refused for the same reasons.
  def answer(:get, %{"fleet_id" => fleet_id, "slug" => slug} = params, actor, _waiter) do
    with {:ok, seq} <- room_place(params, fleet_id, slug, actor),
         {:ok, posts} <-
           Rooms.read_messages(fleet_id, slug, around(seq, params), actor: actor),
         %{} = room <- Rooms.get_room!(fleet_id, slug, actor: actor) do
      placed(%{room: RoomJSON.room(room)}, posts, seq, fleet_id, actor)
    else
      nil -> room_unknown()
      :post_unknown -> refusal(404, "post_unknown")
      {:error, %Ash.Error.Forbidden{} = error} -> refuse_forbidden(fleet_id, error, actor)
      {:error, error} -> refuse(error, actor)
    end
  end

  def answer(:post, %{"fleet_id" => fleet_id, "slug" => slug} = params, actor, _waiter) do
    input =
      params
      |> Map.take(["body", "idempotency_key", "reply_to_id", "quote_request_id"])
      |> Map.merge(%{"fleet_id" => fleet_id, "slug" => slug})

    sent(fleet_id, Rooms.send_message(input, actor: actor), actor)
  end

  # A key's thread is read the way a room is: its posts first, then its head.
  # A key nobody has written to yet has an empty thread. The cursor is the
  # place the posts read reach, to send as after_seq next time. Posts written
  # as a key the agent has muted are left out here too, and the cursor still
  # counts them.
  def answer(:wall_read, %{"fleet_id" => fleet_id, "token_id" => token_id} = params, actor, _w) do
    case Rooms.read_key_thread(fleet_id, token_id, Map.take(params, ["after_seq", "limit"]),
           actor: actor
         ) do
      {:ok, messages} ->
        thread = Rooms.get_key_thread!(fleet_id, token_id, actor: actor)

        paged(
          %{
            thread: %{token_id: String.to_integer(token_id), head_seq: head_seq(thread)},
            cursor: cursor(messages, Map.get(params, "after_seq", 0), head_seq(thread)),
            has_more: Rooms.more_after?(messages),
            messages: []
          },
          messages
          |> Rooms.unmuted(Rooms.muted_keys!(fleet_id, actor))
          |> Enum.map(&RoomJSON.message/1),
          params["max_bytes"]
        )

      {:error, error} ->
        refuse(error, actor)
    end
  end

  # One post on a Key's wall by its place or id, as `:get` reads a room's.
  # Anyone reads a Key's wall.
  def answer(:wall_get, %{"fleet_id" => fleet_id, "token_id" => token_id} = params, actor, _w) do
    with {:ok, seq} <- wall_place(params, fleet_id, token_id, actor),
         {:ok, posts} <-
           Rooms.read_key_thread(fleet_id, token_id, around(seq, params), actor: actor) do
      place = %{thread: %{token_id: String.to_integer(token_id)}}
      placed(place, posts, seq, fleet_id, actor)
    else
      :post_unknown -> refusal(404, "post_unknown")
      {:error, error} -> refuse(error, actor)
    end
  end

  def answer(:wall_post, %{"fleet_id" => fleet_id, "token_id" => token_id} = params, actor, _w) do
    input =
      params
      |> Map.take(["body", "idempotency_key", "reply_to_id"])
      |> Map.merge(%{"fleet_id" => fleet_id, "token_id" => token_id})

    sent(fleet_id, Rooms.send_to_key(input, actor: actor), actor)
  end

  def answer(
        :sync,
        %{
          "fleet_id" => fleet_id,
          "rooms" => rooms,
          "graph" => graph,
          "proposals" => proposals,
          "run" => run
        } = params,
        actor,
        waiter
      ) do
    cursors = Enum.map(rooms, &%{slug: &1["slug"], after_seq: &1["after_seq"]})

    places = %{
      graph: graph["after_seq"],
      project: graph["project"],
      proposals: proposals["after_seq"],
      keys:
        params
        |> Map.get("keys", [])
        |> Enum.map(&%{token_id: &1["token_id"], after_seq: &1["after_seq"]}),
      dms: dm_cursors(params["dms"]),
      quotes: get_in(params, ["quotes", "after_seq"])
    }

    # The body's checks have already opened the mentions' cursor.
    {:ok, mentions_after} = MentionJSON.opened(get_in(params, ["mentions", "after"]))

    # Only a few syncs from one waiter are held open at once; past that a sync
    # answers straight away with what it has.
    with {:ok, synced} <-
           AgentWaits.hold(waiter, &Rooms.sync(fleet_id, cursors, places, actor, &1)),
         {:ok, check_in} <- Agents.check_in(actor, fleet_id, run),
         {:ok, yours} <- yours(fleet_id, actor, %{project: places.project}, mentions_after) do
      muted = Rooms.muted_keys!(fleet_id, actor)

      refused =
        if Enum.any?(synced.rooms, &match?(%{refused: true}, &1)),
          do: refused_code(fleet_id, actor)

      # A conversation's syncs come many times a minute; only a scheduled run
      # asks the chain for the wallet's ETH.
      upkeep = Upkeep.read(actor, fleet_id, run["kind"] == "scheduled")

      answer =
        synced
        |> sync_json(check_in, Map.merge(yours, upkeep), muted, refused)
        |> put_dms(synced.dms)
        |> put_quotes(synced.quotes)

      sent = %{
        graph: places.graph,
        rooms: Map.new(cursors, &{&1.slug, &1.after_seq}),
        keys: Map.new(places.keys, &{&1.token_id, &1.after_seq}),
        mentions: get_in(params, ["mentions", "after"])
      }

      case Budget.sync(answer, params["max_bytes"], sent) do
        {:ok, answer} -> ok(answer)
        {:error, bytes} -> over_budget(bytes)
      end
    else
      {:error, %Ash.Error.Forbidden{}} -> members_only(fleet_id)
      {:error, error} -> refuse(error, actor)
    end
  end

  defp ok(body), do: {200, body, nil}

  defp refusal(status, code), do: {status, Refusal.body(code), nil}

  defp room_place(%{"seq" => seq}, _fleet_id, _slug, _actor), do: {:ok, seq}

  defp room_place(%{"id" => id}, fleet_id, slug, actor) do
    case Rooms.get_room(fleet_id, slug, actor: actor) do
      {:ok, %{id: room_id}} ->
        post_place(Rooms.get_post_in_room(fleet_id, id, room_id, actor: actor))

      # A room the agent can't read, or one the fleet hasn't, is refused as a
      # read of it is.
      {:ok, nil} ->
        with {:ok, _posts} <-
               Rooms.read_messages(fleet_id, slug, %{"limit" => 1}, actor: actor),
             do: nil

      {:error, error} ->
        {:error, error}
    end
  end

  defp wall_place(%{"seq" => seq}, _fleet_id, _token_id, _actor), do: {:ok, seq}

  defp wall_place(%{"id" => id}, fleet_id, token_id, actor) do
    case Rooms.get_key_thread(fleet_id, token_id, actor: actor) do
      {:ok, %{id: room_id}} ->
        post_place(Rooms.get_post_in_room(fleet_id, id, room_id, actor: actor))

      {:ok, nil} ->
        :post_unknown

      {:error, error} ->
        {:error, error}
    end
  end

  defp post_place({:ok, %{seq: seq}}), do: {:ok, seq}
  defp post_place({:ok, nil}), do: :post_unknown
  defp post_place({:error, error}), do: {:error, error}

  # The read that holds the post at `seq` and `context` posts either side.
  defp around(seq, params) do
    context = Map.get(params, "context", 0)
    after_seq = max(seq - context - 1, 0)
    %{"after_seq" => after_seq, "limit" => seq - after_seq + context}
  end

  defp placed(place, posts, seq, fleet_id, actor) do
    muted = Rooms.muted_keys!(fleet_id, actor)
    {before, rest} = Enum.split_while(posts, &(&1.seq < seq))

    case rest do
      [%{seq: ^seq} = post | later] ->
        shown? = Rooms.unmuted([post], muted) != []

        ok(
          Map.merge(place, %{
            seq: seq,
            message: if(shown?, do: RoomJSON.message(post)),
            hidden: if(shown?, do: nil, else: "muted"),
            before: before |> Rooms.unmuted(muted) |> Enum.map(&RoomJSON.message/1),
            after: later |> Rooms.unmuted(muted) |> Enum.map(&RoomJSON.message/1)
          })
        )

      _no_post ->
        refusal(404, "post_unknown")
    end
  end

  # A sync carries the workspace's changes, which only the fleet's members
  # read. Who they are can't be read while the fleet's key ownership is not
  # fresh.
  defp members_only(fleet_id) do
    if Regents.Keyfleet.Chain.fresh?(fleet_id),
      do: refusal(403, "workspace_members_only"),
      else: refreshing()
  end

  # A post answers with how many others posted since the sender's Key last
  # did there, so a reply that crossed it is never missed. A repeat of a post
  # the room already has is answered with that post, and the sender is told
  # nothing new was written.
  defp sent(_fleet_id, {:ok, message}, _actor) do
    status = if Ash.Resource.get_metadata(message, :upsert_skipped), do: 200, else: 201

    {status,
     %{
       message: RoomJSON.message(message),
       posted_after_you: Rooms.posted_after_previous(message)
     }, nil}
  end

  # Standing cannot be read while the fleet's key ownership is not fresh.
  defp sent(fleet_id, {:error, %Ash.Error.Forbidden{} = error}, actor),
    do: refuse_forbidden(fleet_id, error, actor)

  defp sent(_fleet_id, {:error, error}, actor), do: refuse(error, actor)

  # Where reading on starts: the last post read or, with none, the after_seq
  # sent, never past the head, so an after_seq beyond it still reads the next
  # post written.
  defp cursor([], after_seq, head_seq), do: min(after_seq, head_seq)
  defp cursor(messages, _after_seq, _head_seq), do: List.last(messages).seq

  # A page of posts within the caller's `max_bytes`: one cut short reads on
  # from the last post it kept.
  defp paged(bare, shown, max_bytes) do
    case Budget.page(bare, shown, max_bytes) do
      {:ok, shown, false} ->
        ok(%{bare | messages: shown})

      {:ok, kept, true} ->
        ok(%{bare | messages: kept, cursor: List.last(kept).seq, has_more: true})

      {:error, bytes} ->
        over_budget(bytes)
    end
  end

  defp over_budget(bytes),
    do: {422, put_in(Refusal.body("over_budget"), [:error, :details], %{bytes: bytes}), nil}

  defp head_seq(nil), do: 0
  defp head_seq(thread), do: thread.head_seq

  defp sync_json(synced, check_in, yours, muted, refused_code) do
    %{
      rooms: Enum.map(synced.rooms, &synced_room_json(&1, muted, refused_code)),
      keys: Enum.map(synced.keys, &synced_wall_json(&1, muted)),
      graph: synced.graph,
      proposals: %{
        synced.proposals
        | items: Enum.map(synced.proposals.items, &ProposalJSON.summary/1)
      },
      check_in: check_in_json(check_in),
      yours: %{
        yours
        | tasks: Enum.map(yours.tasks, &task_json/1),
          reviews: Enum.map(yours.reviews, &review_ask_json/1),
          goals: Enum.map(yours.goals, &goal_json/1),
          mentions: MentionJSON.changes(yours.mentions)
      }
    }
  end

  # Direct messages are followed only when asked for.
  defp dm_cursors(nil), do: nil
  defp dm_cursors(dms), do: DmAnswer.key_cursors(dms)

  # Direct messages answer only when asked for.
  defp put_dms(answer, nil), do: answer
  defp put_dms(answer, page), do: Map.put(answer, :dms, DmAnswer.changes_json(page))

  # So do the person's requests to quote them.
  defp put_quotes(answer, nil), do: answer

  defp put_quotes(answer, page),
    do:
      Map.put(answer, :quotes, %{
        requests: Enum.map(page.requests, &%{id: &1.id, body: &1.body, asked_at: &1.inserted_at}),
        next_cursor: page.next_cursor,
        has_more: page.has_more
      })

  # A room the agent may not read repeats only the slug it sent, with what
  # keeps it out, as a refusal of that room alone would say.
  defp synced_room_json(%{refused: true, slug: slug}, _muted, refused_code),
    do: %{slug: slug, refused: refused_code}

  defp synced_room_json(room, muted, _refused_code),
    do: %{
      slug: room.slug,
      kind: room.kind,
      head_seq: room.head_seq,
      cursor: room.cursor,
      messages: room.messages |> Rooms.unmuted(muted) |> Enum.map(&RoomJSON.message/1)
    }

  defp synced_wall_json(wall, muted),
    do: %{
      token_id: wall.token_id,
      head_seq: wall.head_seq,
      cursor: wall.cursor,
      messages: wall.messages |> Rooms.unmuted(muted) |> Enum.map(&RoomJSON.message/1)
    }

  # The work waiting on the agent's Key, the whole fleet's or one project's:
  # the key the agent writes as here (its own lowest key, or its shard's),
  # whether a vote of the fleet has stopped that key changing the workspace,
  # the unfinished tasks and the goals the agent joined as it, the submitted
  # tasks it may review, oldest wait first, with how many wait in all, the
  # rooms where others have posted since the Key last did, and the posts that
  # mention the Key after `mentions_after`. An agent with neither a key nor a
  # shard here writes as none, and nothing mentions it.
  defp yours(fleet_id, actor, within, mentions_after) do
    with %{token_id: token_id} <- Keys.identity(actor, fleet_id),
         {:ok, restricted} <- Keys.edits_restricted?(fleet_id, token_id),
         {:ok, tasks} <-
           Graph.tasks_joined_by(fleet_id, token_id, actor.wallet_address, within, actor: actor),
         {:ok, reviews} <- reviews(fleet_id, token_id, restricted, actor, within),
         {:ok, goals} <-
           Graph.goals_joined_by(fleet_id, token_id, actor.wallet_address, within, actor: actor),
         {:ok, mentions} <- Rooms.mention_changes(fleet_id, token_id, mentions_after, actor) do
      {:ok,
       %{
         as_key: token_id,
         edits_restricted: restricted,
         tasks: tasks,
         reviews: reviews.results,
         reviews_waiting: reviews.count,
         goals: goals,
         posted_after_you: Rooms.posted_after_key(fleet_id, token_id),
         mentions: mentions
       }}
    else
      nil ->
        {:ok,
         %{
           as_key: nil,
           edits_restricted: false,
           tasks: [],
           reviews: [],
           reviews_waiting: 0,
           goals: [],
           posted_after_you: [],
           mentions: %{posts: [], next_cursor: mentions_after, has_more: false}
         }}

      error ->
        error
    end
  end

  # The tasks the agent may review as its Key, at the Key's current ownership
  # and from the agent's own wallet, as a review it sent would be stamped
  # (`Regents.Keyfleet.Graph.Checks.KeyActor`). None while a vote restricts the Key's
  # edits, since its review would be refused.
  defp reviews(_fleet_id, _token_id, true, _actor, _within), do: {:ok, %{results: [], count: 0}}

  defp reviews(fleet_id, token_id, false, actor, within) do
    case Keys.current_key(fleet_id, token_id, actor: actor) do
      {:ok, %{ownership_epoch: epoch}} ->
        Graph.review_queue(fleet_id, token_id, epoch, actor.wallet_address, within, actor: actor)

      {:ok, nil} ->
        {:ok, %{results: [], count: 0}}

      error ->
        error
    end
  end

  # An agent without a profile has no check-ins recorded. What it said blocks
  # it is read back as its person sees it.
  defp check_in_json(nil), do: nil

  defp check_in_json(check_in) do
    now = DateTime.utc_now()
    {status, label} = CheckInStatus.derive(check_in, now)

    %{
      status: status,
      status_label: label,
      light: CheckInStatus.light(check_in, now),
      last_check_in_at: check_in.last_check_in_at,
      schedule_minutes: check_in.schedule_minutes,
      schedule_confirmed: check_in.schedule_confirmed_at != nil,
      blocker: check_in.blocker
    }
  end

  defp goal_json(goal) do
    %{id: goal.id, title: goal.title, status: goal.card["status"], version: goal.version}
  end

  defp review_ask_json(task) do
    %{id: task.id, title: task.title, version: task.version, waiting_since: task.changed_at}
  end

  defp task_json(task) do
    %{
      id: task.id,
      title: task.title,
      progress: task.card["progress"],
      next_step: task.next_step,
      version: task.version
    }
  end

  # Who reads beyond the rooms anyone reads, posts, names and creates rooms is
  # the fleet's keys, which cannot be told while the fleet's key ownership is
  # not fresh.
  defp refuse_forbidden(fleet_id, error, actor),
    do: if(Regents.Keyfleet.Chain.fresh?(fleet_id), do: refuse(error, actor), else: refreshing())

  # The code a room refused inside a sync answer carries: the one a refusal of
  # that room alone would answer with.
  defp refused_code(fleet_id, actor),
    do:
      if(Regents.Keyfleet.Chain.fresh?(fleet_id),
        do: not_member(actor),
        else: "ownership_refreshing"
      )

  # An agent with no standing of its own that is paired with a person is told
  # what keeps it from writing as them.
  defp refuse(%Ash.Error.Forbidden{}, actor), do: refusal(403, not_member(actor))

  defp refuse(%RoomUnknownError{}, _actor), do: room_unknown()

  defp refuse(%Ash.Error.Invalid{errors: errors} = error, _actor) do
    named =
      Enum.find_value(@named_refusals, fn kind -> Enum.find(errors, &is_struct(&1, kind)) end)

    refuse_named(named, error)
  end

  defp refuse(_error, _actor), do: refusal(422, "invalid_message")

  defp refuse_named(%UnknownFleetError{}, _error), do: refusal(404, "fleet_unknown")
  defp refuse_named(%RoomUnknownError{}, _error), do: room_unknown()

  defp refuse_named(%KeyUnknownError{fleet_id: fleet_id, token_id: token_id}, _error),
    do: {404, Refusal.key_unknown(fleet_id, token_id), nil}

  defp refuse_named(%NoAgentProfileError{}, _error), do: refusal(404, "profile_not_found")
  defp refuse_named(%SendConflictError{}, _error), do: refusal(422, "idempotency_conflict")
  defp refuse_named(%ReplyOutsideRoomError{}, _error), do: refusal(422, "reply_not_here")
  defp refuse_named(%QuoteUnknownError{}, _error), do: refusal(422, "quote_unknown")
  defp refuse_named(%QuoteDiffersError{}, _error), do: refusal(422, "quote_differs")

  defp refuse_named(%PostLimitError{retry_after: seconds}, _error),
    do: {429, Refusal.body("post_limit_reached"), seconds}

  defp refuse_named(nil, error) do
    if Rooms.taken?(error, :quote_request_id),
      do: refusal(409, "already_quoted"),
      else: refusal(422, "invalid_message")
  end

  defp refuse_room(%Ash.Error.Invalid{errors: errors} = error) do
    cond do
      Enum.any?(errors, &match?(%UnknownFleetError{}, &1)) ->
        refusal(404, "fleet_unknown")

      Enum.any?(errors, &match?(%CreatedRoomLimitError{}, &1)) ->
        refusal(409, "room_limit_reached")

      Enum.any?(errors, &match?(%OwnRoomLimitError{}, &1)) ->
        refusal(409, "own_room_limit_reached")

      Rooms.taken?(error, :slug) ->
        refusal(409, "room_taken")

      Rooms.taken?(error, :name) ->
        name_taken()

      true ->
        refusal(422, "invalid_room")
    end
  end

  defp refuse_room(_error), do: refusal(422, "invalid_room")

  defp refuse_topic(%RoomUnknownError{}), do: room_unknown()

  defp refuse_topic(%Ash.Error.Invalid{errors: errors} = error) do
    cond do
      Enum.any?(errors, &match?(%UnknownFleetError{}, &1)) ->
        refusal(404, "fleet_unknown")

      Enum.any?(errors, &match?(%{field: :kind}, &1)) ->
        refusal(422, "room_not_open")

      Rooms.taken?(error, :name) ->
        name_taken()

      too_soon = Enum.find(errors, &match?(%RenameTooSoonError{}, &1)) ->
        {429, Refusal.body("rename_too_soon"), too_soon.retry_after}

      true ->
        refusal(422, "invalid_topic")
    end
  end

  defp refuse_topic(_error), do: refusal(422, "invalid_topic")

  # Another room of the fleet already goes by this name.
  defp name_taken, do: refusal(409, "name_taken")

  defp not_member(%Agent{pairing: :person_not_here}), do: "person_not_here"
  defp not_member(%Agent{}), do: "not_a_member"

  defp refreshing, do: refusal(503, "ownership_refreshing")

  defp room_unknown, do: refusal(404, "room_unknown")
end
