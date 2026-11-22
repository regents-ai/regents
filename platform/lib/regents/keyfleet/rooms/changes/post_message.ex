defmodule Regents.Keyfleet.Rooms.Changes.PostMessage do
  @moduledoc """
  Puts one line in its room, of the kind the action names (`kind: :post` or
  `kind: :room_named`), or hands back the line this sender already made. With
  `in: :room` the room is the fleet's room named by `slug`; with `in: :key` it
  is the thread of the key `token_id`, opened by its first post, and the line
  is marked `in_key_thread`.

  A line is written as the author's key in the fleet
  (`Regents.Keyfleet.Keys.identity/2`), which is kept on the line as `as_key`. An
  agent writing as the person it is paired with writes the person's line,
  marked with its profile as `via_agent_profile`. A post keeps the Keys its
  words mention (`Regents.Keyfleet.Rooms.Mentions`).

  A sender names every post with a key of its own. If the same key arrives again
  with the same words, the room keeps the post it already has and answers with
  it; the same key with different words is a mistake and is refused, so a sender
  that never heard the answer can simply ask again.
  """
  use Ash.Resource.Change

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.Human
  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Errors.NoAgentProfileError
  alias Regents.Keyfleet.Rooms.Errors.NoKeyToWriteAsError
  alias Regents.Keyfleet.Rooms.Errors.ReplyOutsideRoomError
  alias Regents.Keyfleet.Rooms.Errors.RoomUnknownError
  alias Regents.Keyfleet.Rooms.Errors.SendConflictError
  alias Regents.Keyfleet.Rooms.Mentions
  alias Regents.Keyfleet.Rooms.Sequence

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    changeset
    |> Ash.Changeset.before_action(
      &place(&1, actor, Keyword.fetch!(opts, :kind), Keyword.fetch!(opts, :in))
    )
    |> Ash.Changeset.after_action(&confirm/2)
  end

  defp place(changeset, actor, kind, into) do
    reply_to_id = Ash.Changeset.get_argument(changeset, :reply_to_id)

    case room(changeset, into, actor) do
      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)

      {:ok, room} ->
        if answers_this_room?(reply_to_id, room, actor),
          do: write(changeset, room, actor, kind),
          else:
            Ash.Changeset.add_error(
              changeset,
              ReplyOutsideRoomError.exception(reply_to_id: reply_to_id)
            )
    end
  end

  defp room(changeset, :room, actor) do
    fleet_id = Ash.Changeset.get_argument(changeset, :fleet_id)
    slug = Ash.Changeset.get_argument(changeset, :slug)

    case Rooms.get_room!(fleet_id, slug, actor: actor) do
      nil -> {:error, RoomUnknownError.exception(fleet_id: fleet_id, slug: slug)}
      room -> {:ok, room}
    end
  end

  # The action has already checked that the fleet issued the key.
  defp room(changeset, :key, _actor) do
    Rooms.open_key_thread(
      Ash.Changeset.get_argument(changeset, :fleet_id),
      Ash.Changeset.get_argument(changeset, :token_id),
      actor: %System{}
    )
  end

  defp answers_this_room?(nil, _room, _actor), do: true

  defp answers_this_room?(reply_to_id, room, actor),
    do: Rooms.get_post_in_room!(room.fleet_id, reply_to_id, room.id, actor: actor) != nil

  # Who the line is written as is read once more under the room's lock: a key
  # that changed hands since the policy looked leaves nothing to write as.
  defp write(changeset, room, actor, kind) do
    Sequence.lock_room!(room.id)

    case Regents.Keyfleet.Keys.identity(actor, room.fleet_id) do
      nil ->
        Ash.Changeset.add_error(changeset, NoKeyToWriteAsError.exception(fleet_id: room.fleet_id))

      identity ->
        write_as(changeset, room, actor, kind, identity)
    end
  end

  defp write_as(changeset, room, actor, kind, %{token_id: as_key, wallet: wallet} = identity) do
    body = Ash.Changeset.get_argument(changeset, :body)
    idempotency_key = Ash.Changeset.get_argument(changeset, :idempotency_key)
    earlier = earlier_post(room.fleet_id, actor, idempotency_key)

    case author(actor, identity, as_key, author_wallet(earlier, wallet)) do
      nil ->
        Ash.Changeset.add_error(changeset, NoAgentProfileError.exception([]))

      {author, profiles} ->
        changeset
        |> Ash.Changeset.put_context(:author_profiles, profiles)
        |> Ash.Changeset.force_change_attributes(
          Map.merge(author, %{
            kind: kind,
            in_key_thread: room.kind == :key,
            fleet_id: room.fleet_id,
            room_id: room.id,
            seq: seq(room, earlier),
            body: body,
            body_digest: digest(body),
            mentions: mentions(kind, body),
            idempotency_key: idempotency_key,
            reply_to_id: Ash.Changeset.get_argument(changeset, :reply_to_id),
            quote_request_id: Ash.Changeset.get_argument(changeset, :quote_request_id)
          })
        )
    end
  end

  defp earlier_post(fleet_id, actor, idempotency_key),
    do:
      Rooms.get_post_under_send_key!(
        fleet_id,
        Rooms.sender_wallets(actor),
        idempotency_key,
        actor: actor
      )

  # A retry is written under the wallet of the first post, so the database
  # hands that post back instead of taking a second one.
  defp author_wallet(nil, wallet), do: wallet
  defp author_wallet(earlier, _wallet), do: earlier.author_wallet

  # A repeat keeps the place its post already holds, so the room's order stays
  # unbroken whether or not the first attempt ever reached the sender.
  defp seq(room, nil), do: Sequence.next!(room.id)
  defp seq(_room, earlier), do: earlier.seq

  # An agent writes from its own wallet with its profile; a person from the
  # wallet holding the key they write as, and an agent writing for its person
  # the same way, marked with its profile. An agent without a profile has
  # nothing to write as: nil.
  defp author(%Human{}, _identity, as_key, wallet),
    do: {person(as_key, wallet, nil), %{agent_profile: nil, via_agent_profile: nil}}

  defp author(%Agent{} = actor, identity, as_key, wallet) do
    case Regents.Keyfleet.Agents.get_my_profile!(actor: actor, load: [:human_backed]) do
      nil -> nil
      profile -> agent_author(profile, identity, as_key, wallet)
    end
  end

  defp agent_author(profile, %{for_person: true}, as_key, wallet),
    do: {person(as_key, wallet, profile.id), %{agent_profile: nil, via_agent_profile: profile}}

  defp agent_author(profile, _identity, as_key, wallet),
    do:
      {%{
         author_kind: :agent,
         author_wallet: wallet,
         as_key: as_key,
         agent_profile_id: profile.id,
         via_agent_profile_id: nil
       }, %{agent_profile: profile, via_agent_profile: nil}}

  defp person(as_key, wallet, via),
    do: %{
      author_kind: :human,
      author_wallet: wallet,
      as_key: as_key,
      agent_profile_id: nil,
      via_agent_profile_id: via
    }

  # A post asks something of the Keys its words mention; a room's naming line
  # asks nothing.
  defp mentions(:post, body), do: Mentions.parse(body)
  defp mentions(:room_named, _body), do: []

  defp digest(body), do: :sha256 |> :crypto.hash(body) |> Base.encode16(case: :lower)

  # The database settles which post a send key names. Whatever comes back must
  # be the post these words were meant to make, in the room they were meant for.
  defp confirm(changeset, message) do
    body = Ash.Changeset.get_argument(changeset, :body)

    if message.body_digest == digest(body) and
         message.room_id == Ash.Changeset.get_attribute(changeset, :room_id) do
      # A post is answered with its author, the way the room answers it.
      {:ok, Map.merge(message, changeset.context.author_profiles)}
    else
      {:error,
       SendConflictError.exception(
         idempotency_key: Ash.Changeset.get_argument(changeset, :idempotency_key)
       )}
    end
  end
end
