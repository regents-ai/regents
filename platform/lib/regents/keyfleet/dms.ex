defmodule Regents.Keyfleet.Dms do
  @moduledoc """
  Direct messages: one Key of a fleet writing privately to another Key of the
  same fleet. A pair of Keys shares one conversation, opened by its first
  message (`Regents.Keyfleet.Dms.Conversation`); each message is a line in it
  (`Regents.Keyfleet.Dms.Message`), and a Key may block another (`Regents.Keyfleet.Dms.Block`).

  Everything belongs to the Keys, never to the people holding them. Who may
  read and send as a Key is decided at each request by who holds it now
  (`Regents.Keyfleet.Dms.Checks.KeyHolder`, by the rule `Regents.Keyfleet.Keys.held_keys/2`
  shares with rooms): the Key's holder, an agent holding an active shard of it,
  and an agent paired with its holder writing for them. A Key sold takes its
  blocks to the new holder, who sees only messages from when they got the Key:
  every read of messages, conversations and the inbox shows a Key's holder
  only what was sent or received while the Key had its current holder
  (`Regents.Keyfleet.Dms.Message`'s `shown_to`). Nothing older is deleted, and the
  other side of each conversation still sees all of it.

  ## The rules

  Sean's four open answers, built with the recommended choice. This is the one
  place they are stated; each names where it lives, so a different answer is a
  small change there.

  1. **Blocks are per Key and follow it when sold.** A block is kept by the
     blocking Key's number (`Regents.Keyfleet.Dms.Block`). A blocked Key's messages
     still save, and its conversation shows in the blocker's Blocked inbox
     instead of the main one (`Regents.Keyfleet.Dms.Conversation`'s `:inbox` read, its
     `blocked` argument). Catch-up (`changes/3`) leaves out what a blocked Key
     sent (`Regents.Keyfleet.Dms.Message`'s `:changes` read).
  2. **Only between Keys of the same fleet.** A conversation and each of its
     messages carry one `fleet_id`, and a send names its fleet once
     (`Regents.Keyfleet.Dms.Message`'s `:send` action).
  3. **Deleting is per side.** A Key's holder deletes a conversation from
     that Key's view only: every message so far leaves it, and the other side
     keeps its own (`Regents.Keyfleet.Dms.Conversation`'s `:clear`). Each side may also
     drop its messages after 1, 7, 30 or 90 days, or keep them
     (`:set_auto_delete`), for its own view. A scheduled job removes a message
     every hour once neither side keeps it (`Regents.Keyfleet.Dms.Message`'s
     `:remove_expired` and its `oban` schedule). Sean, 21 Oct 2026: nobody
     removes the other side's messages.
  4. **No notifications; files only as links.** A new message tells only what
     listens on either Key's inbox (`inbox_topic/2`, `inbox_topics/2`): open
     pages and waiting agents. Nothing else is sent.
     A message carries a file only as a `link` part (`Regents.Keyfleet.Dms.Part`). Room
     mutes are unchanged and do not touch DMs; there is no DM mute.

  Also: a Key sends at most 300 messages an hour, and opening a new
  conversation has no daily cap (`Regents.Keyfleet.Dms.Changes.LimitSends`, counted
  from the messages it stored).
  """
  use Ash.Domain

  alias Regents.Keyfleet.Dms.Checks.KeyHolder
  alias Regents.Keyfleet.Dms.Conversation

  @changes_page 50

  resources do
    resource Regents.Keyfleet.Dms.Conversation do
      define :inbox, action: :inbox, args: [:fleet_id, :token_id]

      define :get_conversation,
        action: :between,
        args: [:fleet_id, :token_id, :other_token_id],
        not_found_error?: false

      define :open_conversation, action: :open
      define :set_auto_delete, action: :set_auto_delete, args: [:token_id, :auto_delete_days]
      define :delete_conversation, action: :clear, args: [:token_id]
    end

    resource Regents.Keyfleet.Dms.Message do
      define :send_dm, action: :send

      define :read_conversation,
        action: :in_conversation,
        args: [:fleet_id, :token_id, :other_token_id]

      define :latest_in_conversation,
        action: :latest,
        args: [:fleet_id, :token_id, :other_token_id]

      define :read_changes, action: :changes, args: [:fleet_id, :token_ids, :after_seqs]
      define :search_messages, action: :search, args: [:fleet_id, :token_ids, :query]
    end

    resource Regents.Keyfleet.Dms.ReadMark do
      define :mark_conversation_read, action: :mark, args: [:conversation_id, :seq]
      define :conversation_read_marks, action: :in_conversations, args: [:conversation_ids]
    end

    resource Regents.Keyfleet.Dms.Block do
      define :block_key, action: :block, args: [:fleet_id, :blocker_token_id, :blocked_token_id]
      define :unblock, action: :unblock
      define :blocks_of_key, action: :of_key, args: [:fleet_id, :token_id]

      define :get_block,
        action: :pair,
        args: [:fleet_id, :token_id, :other_token_id],
        not_found_error?: false
    end
  end

  @doc """
  Where the pages open on one Key's messages hear what changed in them, after
  it commits: "dm_head" with `%{conversation_id, seq, from_token_id}` for a new
  message to or from the Key, and "dm_deleted" with `%{conversation_id}` when
  the Key's side deletes a conversation of its.
  """
  def inbox_topic(fleet_id, token_id), do: "keyfleet:dms:#{fleet_id}:#{token_id}"

  @doc """
  The topics of every Key `actor` holds now in the fleet (`inbox_topic/2`),
  by the rule its reads and sends are checked by; none while the fleet's key
  ownership is not fresh. They are the Keys `changes/3` reads for.
  """
  def inbox_topics(fleet_id, actor),
    do: Enum.map(KeyHolder.held(actor, fleet_id), &inbox_topic(fleet_id, &1))

  @doc """
  What `actor` has not read yet of its Keys' messages in a fleet: the messages
  to or from any Key it holds now (`inbox_topics/2`'s Keys) since it got that
  Key, oldest first, at most #{@changes_page} at a time, without those a Key it
  reads for has blocked.

  `cursors` maps a Key's number to how far its messages have been read. Each
  Key is read after its own place, and a Key held now that `cursors` leaves out
  is read from the start of its holding, so a Key the actor gets later loses
  nothing. A Key named and not held now is left out.

  `{:ok, %{messages, keys, has_more}}`. `keys` gives, for each Key held now
  that was named or has a message on the page, the `%{token_id, cursor}` to
  send next time. The page is in order of the fleet's message places, so every
  message of a Key up to the page's last place is on it, and its cursor moves
  there. An actor holding no Key of the fleet now is forbidden. Nothing is
  marked as read, and asking again is always safe.
  """
  def changes(fleet_id, cursors, actor) do
    held = KeyHolder.held(actor, fleet_id)

    with {:ok, messages} <-
           read_changes(
             fleet_id,
             held,
             Enum.map(held, &Map.get(cursors, &1, 0)),
             %{limit: @changes_page},
             actor: actor,
             load: [:via_agent]
           ) do
      {:ok,
       %{
         messages: messages,
         keys: key_cursors(held, cursors, messages),
         has_more: more_after?(messages)
       }}
    end
  end

  defp key_cursors(held, cursors, messages) do
    last = if messages == [], do: 0, else: List.last(messages).seq
    on_page = MapSet.new(Enum.flat_map(messages, &[&1.from_token_id, &1.to_token_id]))

    for token_id <- held,
        Map.has_key?(cursors, token_id) or token_id in on_page,
        do: %{token_id: token_id, cursor: Kernel.max(Map.get(cursors, token_id, 0), last)}
  end

  @doc """
  Whether messages wait after the last of `messages`, a page read with
  `read_conversation` or `changes/3`. Nothing read means nothing waits.
  """
  def more_after?([]), do: false
  def more_after?(messages), do: messages |> List.last() |> Ash.Resource.get_metadata(:more_after)

  @doc """
  Takes away Key `token_id`'s block of `other_token_id`, if it has one:
  `{:ok, block | nil}`. Unblocking a Key that isn't blocked changes nothing.
  """
  def unblock_key(fleet_id, token_id, other_token_id, opts) do
    case get_block(fleet_id, token_id, other_token_id, opts) do
      {:ok, nil} -> {:ok, nil}
      {:ok, block} -> with :ok <- unblock(block, opts), do: {:ok, block}
      {:error, error} -> {:error, error}
    end
  end

  @doc "The Key on the other side of a conversation from `token_id`."
  def other_key(%Conversation{key_a: token_id, key_b: other}, token_id), do: other
  def other_key(%Conversation{key_a: other}, _token_id), do: other
end
