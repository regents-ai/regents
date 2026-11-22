defmodule RegentsWeb.Keyfleet.AgentTools.Fleets.Answer do
  @moduledoc """
  What an agent reads about itself and a fleet, the same over its signed
  requests and as the Claude connector's tools (`RegentsWeb.Keyfleet.AgentTools.Fleets`):
  its standing (`:doctor`), its checkpoint (`:checkpoint`,
  `:save_checkpoint`), what has been happening (`:activity`), a search of it
  (`:search`), one proposal with its votes (`:proposal`), whether a request it sent ran (`:receipts`),
  what a pasted address names (`:link`, `RegentsWeb.Keyfleet.Links`), what a write
  would do before it is sent (`:preview`, `RegentsWeb.Keyfleet.Preview`) and what its
  live feed sent after a cursor (`:missed`, `Regents.Keyfleet.Feed`). Each answer
  is `{status, body, nil}`; `params` is the signed request's JSON, its body
  with the fleet's id. A link and a preview read nothing from the thing
  itself and write nothing.

  The standing is read in one go, so the agent learns what it may do and
  what is still missing before it tries: who it signed in as, its pairing and
  profile, the Key it acts as and the Keys it may act as, whether the fleet's
  key ownership is fresh, what it may read and write by `Regents.Keyfleet.Access`'s
  table, and each missing thing with the refusal it would meet, in that
  refusal's own words (`RegentsWeb.Keyfleet.Standing`). Nothing is written. The
  person's World ID number is never answered, only whether a verified person
  stands behind the agent. Rules narrower than the table, such as a poll's
  starter ending it, are each operation's own.

  A checkpoint is where the agent left off in the fleet
  (`Regents.Keyfleet.Agents.Checkpoint`), saved from the revision it read; a save
  from any other revision is refused with the checkpoint as it is now, so the
  agent merges and saves again.

  The activity is the fleet's, newest first, as its hall shows it
  (`Regents.Keyfleet.Activity`): posts, workspace changes, Key sales and transfers,
  shards and proposals. Posts in rooms other than the ones anyone reads, and
  the workspace's changes, show only to an agent acting as one of the fleet's
  Keys. The cursor `Regents.Keyfleet.Activity` answers must never leave the server,
  so the agent is given it sealed, for this fleet, and hands it back
  unchanged to read the next page. A sealed cursor lasts an hour; past that
  the agent reads from the newest page again.

  A search finds the fleet's posts, direct messages and workspace items whose
  words match, and the notebooks whose title or description holds the query,
  newest first, as the reader may read each (`Regents.Keyfleet.Search`), each with
  the address of the page it is on. A page's cursor is handed back
  unchanged to read on from it; it never runs out.

  A receipt says whether a request ran, asked by the key the agent sent it
  with, so an agent whose answer never arrived learns what happened before
  it sends anything again. One key may have made a post (its send key,
  `idempotency_key`), a workspace write (its `command_id`), or both. A post is
  found as a retry of it would be, under the agent's wallet or its person's
  (`Regents.Keyfleet.Rooms.sender_wallets/1`), and answered only when this agent sent
  it, as itself or for its person: the post as stored, its words exactly as
  kept. A workspace write is found under the agent's own wallet, as
  whichever Key it was sent as, answered with what the write answered. The
  workspace part reads from its read tables, as every workspace read does: a
  write whose answer was lost can take a moment to show, and a write sent
  again with its command id never runs twice.

  The missed events are what the agent's live feed would replay to a
  reconnect sending `cursor` as `Last-Event-ID` (`Regents.Keyfleet.Feed.missed/3`),
  up to the settled moment, thirty seconds before the database's now: the
  same events, oldest first, up to 100, with `cursor` always the settled
  moment's, to send next time. Reading on from that cursor passes no post
  committed within those thirty seconds of its id: a later read answers it.
  A cursor later than the settled moment, an id the feed sent lately,
  answers no events, so the next read can repeat what the feed sent, told
  apart by id. Any id from the feed shares a reconnect's gap, since a
  message stamped before it and still being saved when the feed dropped can
  be passed, and a sync covers it. Where the feed would resync, past 100
  events after the cursor or for a cursor that is no event's id, `resync`
  is true and no events are answered: catch up with a sync, then read on
  from `cursor`. With no cursor the read starts from
  the settled moment. A failure reading the events or the database's clock
  answers 503 `feed_unavailable`, to be sent again; a failure reading the
  agent's place in its fleets is a 500, as on any route.
  """

  alias Regents.Keyfleet.{
    Access,
    Activity,
    Agents,
    Capabilities,
    Feed,
    Fleets,
    Graph,
    Proposals,
    Rooms,
    Search
  }

  alias Regents.Account.Actors.{Agent, Human}
  alias Regents.Keyfleet.Agents.Upkeep
  alias Regents.Keyfleet.Graph.Event

  alias RegentsWeb.Keyfleet.{
    Links,
    ProposalJSON,
    Refusal,
    RoomJSON,
    SearchJSON,
    Standing
  }

  @salt "agent activity cursor"
  @cursor_seconds 3600
  @votes_page 20

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) :: {pos_integer(), map(), nil}
  def answer(:doctor, %{"fleet_id" => fleet_id}, actor, _waiter) do
    with %{} = fleet <- Fleets.get_fleet!(fleet_id),
         {:ok, standing} <- Standing.read(actor, fleet_id) do
      class = Access.class(actor, fleet_id)
      upkeep = Upkeep.read(actor, fleet_id, true)

      ok(%{
        fleet_id: fleet_id,
        fleet_name: fleet.name,
        agent: %{
          wallet_address: actor.wallet_address,
          chain_id: actor.chain_id,
          verification_method: actor.verification_method,
          sign_in_expires_at: actor.receipt_expires_at,
          registry_listing: actor.registry_url,
          human_backed: actor.human_id != nil
        },
        pairing: pairing(actor.pairing),
        profile: standing.profile && Map.take(standing.profile, [:id, :name, :declared_harness]),
        ownership_fresh: standing.fresh,
        key: standing.key,
        keys: Enum.map(standing.keys, & &1.token_id),
        may:
          Map.new(Access.components(), fn {component, _classes} ->
            {component,
             %{
               read: Access.enough?(class, :read, component),
               write: Access.enough?(class, :write, component)
             }}
          end),
        missing: standing.missing,
        setup: Upkeep.setup(actor, fleet_id, standing.profile, upkeep),
        gas: upkeep.gas,
        versions: Capabilities.versions(),
        build: Application.fetch_env!(:regents, :build)
      })
    else
      nil -> refusal(404, "fleet_unknown")
      {:error, _error} -> refusal(503, "profile_unavailable")
    end
  end

  def answer(:checkpoint, %{"fleet_id" => fleet_id}, actor, _waiter) do
    in_fleet(fleet_id, fn ->
      with {:ok, checkpoint} <- Agents.checkpoint(fleet_id, actor: actor),
           do: {:ok, %{checkpoint: view(checkpoint)}}
    end)
  end

  def answer(:save_checkpoint, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    %{"expected_revision" => expected, "state" => state} = params

    in_fleet(fleet_id, fn ->
      case Agents.save_checkpoint(actor, fleet_id, expected, state) do
        {:ok, checkpoint} -> {:ok, %{checkpoint: view(checkpoint)}}
        other -> other
      end
    end)
  end

  def answer(:activity, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    with %{} <- Fleets.get_fleet!(fleet_id),
         {:ok, cursor} <- opened(fleet_id, params["cursor"]) do
      %{items: items, cursor: next} = Activity.page(fleet_id, cursor, actor: actor)
      ok(%{items: items, has_more: next != nil, cursor: sealed(fleet_id, next)})
    else
      nil -> refusal(404, "fleet_unknown")
      :error -> refusal(422, "activity_cursor_unknown")
    end
  end

  def answer(:search, %{"fleet_id" => fleet_id, "query" => query} = params, actor, _waiter) do
    limit = Map.get(params, "limit", Search.limits().default)

    with %{} <- Fleets.get_fleet!(fleet_id),
         {:ok, cursor} <- SearchJSON.opened(params["cursor"]),
         {:ok, %{matches: matches, cursor: next}} <-
           Search.page(fleet_id, query, cursor, limit, actor) do
      ok(%{
        matches: Enum.map(matches, &SearchJSON.match(fleet_id, &1)),
        has_more: next != nil,
        cursor: SearchJSON.cursor(next)
      })
    else
      nil -> refusal(404, "fleet_unknown")
      :error -> refusal(422, "search_cursor_unknown")
      {:error, :query} -> refusal(422, "search_query_invalid")
    end
  end

  def answer(:receipts, %{"fleet_id" => fleet_id, "idempotency_key" => key}, actor, _waiter) do
    with %{} <- Fleets.get_fleet!(fleet_id),
         {:ok, post} <- post(fleet_id, key, actor),
         {:ok, writes} <- writes(fleet_id, key, actor) do
      receipts = List.wrap(post) ++ writes
      ok(%{idempotency_key: key, executed: receipts != [], receipts: receipts})
    else
      nil -> refusal(404, "fleet_unknown")
      :refreshing -> refusal(503, "ownership_refreshing")
      {:error, _error} -> refusal(503, "graph_unavailable")
    end
  end

  def answer(:proposal, %{"fleet_id" => fleet_id} = params, _actor, _waiter) do
    %{"number" => number, "votes_after_seq" => after_seq} = params

    case Fleets.get_fleet!(fleet_id) do
      nil -> refusal(404, "fleet_unknown")
      _fleet -> proposal(fleet_id, number, after_seq)
    end
  end

  def answer(:link, %{"url" => url}, actor, _waiter) do
    case Links.resolve(url, actor) do
      {:ok, link} -> ok(Map.put(link, :url, url))
      :unknown -> refusal(422, "link_unknown")
    end
  end

  def answer(:missed, params, actor, _waiter) do
    case params do
      %{"cursor" => cursor} -> actor |> Feed.open() |> Feed.missed(cursor, :settled) |> missed()
      %{} -> missed(with {:ok, cursor} <- Feed.settled(), do: {:ok, [], cursor})
    end
  end

  defp ok(body), do: {200, body, nil}
  defp refusal(status, code), do: {status, Refusal.body(code), nil}

  defp proposal(fleet_id, number, after_seq) do
    case Proposals.get_by_number(fleet_id, number) do
      nil ->
        refusal(404, "proposal_unknown")

      proposal ->
        {votes, more?} = Proposals.votes_after(proposal.id, after_seq, @votes_page)

        ok(%{
          proposal: ProposalJSON.detail(proposal, Proposals.status(proposal)),
          ballots: Proposals.key_ballots(proposal),
          votes: Enum.map(votes, &ProposalJSON.vote/1),
          votes_next_cursor:
            votes |> List.last(%{record_seq: after_seq}) |> Map.fetch!(:record_seq),
          votes_has_more: more?
        })
    end
  end

  defp missed({:ok, events, cursor}), do: ok(%{events: events, cursor: cursor, resync: false})
  defp missed({:resync, cursor}), do: ok(%{events: [], cursor: cursor, resync: true})
  defp missed({:error, _error}), do: refusal(503, "feed_unavailable")

  defp pairing(%Human{}), do: "paired"
  defp pairing(:person_not_here), do: "person_not_here"

  defp in_fleet(fleet_id, act) do
    if fleet_id in Fleets.catalog_ids() do
      case act.() do
        {:ok, answer} ->
          ok(answer)

        {:stale, current} ->
          {409,
           put_in(Refusal.body("checkpoint_conflict"), [:error, :details], %{
             checkpoint: view(current)
           }), nil}

        {:error, error} ->
          unsaved(error)
      end
    else
      refusal(404, "fleet_unknown")
    end
  end

  defp unsaved(error) do
    if Agents.unpaired?(error),
      do: refusal(403, "agent_not_paired"),
      else: refusal(503, "checkpoint_unavailable")
  end

  defp view(nil), do: nil
  defp view(checkpoint), do: Map.take(checkpoint, [:fleet_id, :revision, :state, :updated_at])

  defp opened(_fleet_id, nil), do: {:ok, nil}

  defp opened(fleet_id, sealed) do
    case Phoenix.Token.decrypt(RegentsWeb.Endpoint, @salt, sealed, max_age: @cursor_seconds) do
      {:ok, {^fleet_id, cursor}} -> {:ok, cursor}
      _expired_or_other -> :error
    end
  end

  defp sealed(_fleet_id, nil), do: nil

  defp sealed(fleet_id, cursor),
    do: Phoenix.Token.encrypt(RegentsWeb.Endpoint, @salt, {fleet_id, cursor})

  defp post(fleet_id, key, actor) do
    with {:ok, %{} = message} <-
           Rooms.get_post_under_send_key(fleet_id, Rooms.sender_wallets(actor), key,
             actor: actor,
             load: [:room, :agent_profile, :via_agent_profile]
           ),
         {:ok, %{id: profile_id}} <- Agents.get_my_profile(actor: actor),
         true <- profile_id in [message.agent_profile_id, message.via_agent_profile_id] do
      {:ok, post_receipt(message)}
    else
      {:ok, nil} -> {:ok, nil}
      false -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  defp post_receipt(%{room: %{kind: :key, token_id: token_id}} = message),
    do: %{kind: "post", room: nil, wall: token_id, message: RoomJSON.message(message)}

  defp post_receipt(%{room: room} = message),
    do: %{kind: "post", room: room.slug, wall: nil, message: RoomJSON.message(message)}

  defp writes(fleet_id, key, actor) do
    wallet = String.downcase(actor.wallet_address)

    case Graph.command_records(fleet_id, key, actor: actor) do
      {:ok, records} ->
        receipts =
          for record <- records,
              match?({_key, "agent", ^wallet}, Event.member(record.payload["principal"])),
              do: write_receipt(record)

        {:ok, receipts}

      {:error, %Ash.Error.Forbidden{}} ->
        members_only(fleet_id)

      {:error, error} ->
        {:error, error}
    end
  end

  # Only the fleet's members read its workspace. An agent that isn't one
  # now has no workspace write to find, and one sent again is refused, so
  # its posts are answered alone; who the members are can't be told while
  # the fleet's key ownership is not fresh.
  defp members_only(fleet_id),
    do: if(Regents.Keyfleet.Chain.fresh?(fleet_id), do: {:ok, []}, else: :refreshing)

  defp write_receipt(record) do
    {as_key, _kind, _wallet} = Event.member(record.payload["principal"])

    %{
      kind: "workspace",
      op: record.payload["op"],
      as_key: as_key,
      seq: record.seq,
      at: record.timestamp,
      result: record.payload["result"]
    }
  end
end
