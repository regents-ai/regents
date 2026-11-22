defmodule RegentsWeb.Keyfleet.AgentTools.Dms.Answer do
  @moduledoc """
  What direct messages (`Regents.Keyfleet.Dms`) answer an agent, the same over its
  signed requests (`RegentsWeb.Keyfleet.AgentDmController`) and as the Claude
  connector's tools (`RegentsWeb.Keyfleet.AgentTools.Dms`): a Key's conversations,
  reading and sending in one, deleting it or setting it to delete itself, the
  Keys it has blocked, and catching up on every Key the agent holds. Each
  answer is `{status, body, retry_after}`, with `retry_after` in seconds or
  nil; `params` is the signed request's JSON, its body with the names in its
  address (`fleet_id`, `token_id`, `other_token_id`).

  Each request but catching up names the Key the agent acts as, which must be
  one it holds now: its own, one it holds a shard of, or its paired person's.
  """

  alias Regents.Account.Actors.Agent
  alias Regents.Keyfleet.Dms
  alias Regents.Keyfleet.Dms.Errors.SameKeyError
  alias Regents.Keyfleet.Dms.Errors.SendLimitError
  alias Regents.Keyfleet.Graph.Errors.UnknownFleetError
  alias Regents.Keyfleet.Rooms.Errors.KeyUnknownError
  alias Regents.Keyfleet.Rooms.Errors.NoAgentProfileError
  alias Regents.Keyfleet.Rooms.Errors.SendConflictError
  alias RegentsWeb.Keyfleet.Refusal

  @message_fields [
    :id,
    :seq,
    :conversation_id,
    :from_token_id,
    :to_token_id,
    :body,
    :parts,
    :author_wallet,
    :inserted_at
  ]

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) ::
          {pos_integer(), map(), pos_integer() | nil}
  def answer(op, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    case run(op, params, actor: actor) do
      {:ok, body} -> {200, body, nil}
      {:sent, status, body} -> {status, body, nil}
      error -> refuse(error, fleet_id, actor)
    end
  end

  # A Key's conversations: the main inbox and, apart, those with Keys it has
  # blocked.
  defp run(:inbox, %{"fleet_id" => fleet_id, "token_id" => token_id}, opts) do
    token_id = String.to_integer(token_id)

    with {:ok, main} <- Dms.inbox(fleet_id, token_id, opts),
         {:ok, blocked} <- Dms.inbox(fleet_id, token_id, %{blocked: true}, opts) do
      {:ok,
       %{
         conversations: Enum.map(main, &conversation_json(&1, token_id)),
         blocked_conversations: Enum.map(blocked, &conversation_json(&1, token_id))
       }}
    end
  end

  # The messages are read before the conversation, so the conversation
  # answered is never behind the messages answered with it.
  defp run(:read, params, opts) do
    {fleet_id, token_id, other} = keys(params)
    page = Map.take(params, ["after_seq", "limit"])

    with {:ok, messages} <- Dms.read_conversation(fleet_id, token_id, other, page, opts),
         {:ok, conversation} <- Dms.get_conversation(fleet_id, token_id, other, opts) do
      {:ok,
       %{
         conversation: conversation && conversation_json(conversation, token_id),
         cursor: cursor(messages, Map.get(params, "after_seq", 0), conversation),
         has_more: Dms.more_after?(messages),
         messages: Enum.map(messages, &message_json/1)
       }}
    end
  end

  # A repeat of a message already sent is answered with that message, and the
  # sender is told nothing new was written.
  defp run(:send, params, opts) do
    {fleet_id, token_id, other} = keys(params)

    input =
      params
      |> Map.take(["body", "idempotency_key", "parts"])
      |> Map.merge(%{"fleet_id" => fleet_id, "from_token_id" => token_id, "to_token_id" => other})

    with {:ok, message} <- Dms.send_dm(input, Keyword.put(opts, :load, [:via_agent])) do
      status = if Ash.Resource.get_metadata(message, :upsert_skipped), do: 200, else: 201
      {:sent, status, %{message: message_json(message)}}
    end
  end

  # Deletes the conversation from this Key's side only; the other Key keeps
  # its own.
  defp run(:delete, params, opts) do
    {fleet_id, token_id, other} = keys(params)

    with {:ok, conversation} <- conversation(fleet_id, token_id, other, opts),
         {:ok, _cleared} <- Dms.delete_conversation(conversation, token_id, opts) do
      {:ok, %{deleted_conversation_id: conversation.id}}
    end
  end

  defp run(:auto_delete, %{"days" => days} = params, opts) do
    {fleet_id, token_id, other} = keys(params)

    with {:ok, conversation} <- conversation(fleet_id, token_id, other, opts),
         {:ok, conversation} <- Dms.set_auto_delete(conversation, token_id, days, opts) do
      {:ok, %{conversation: conversation_json(conversation, token_id)}}
    end
  end

  # Keeping a conversation's messages is setting its days to none, as its tool sends.
  defp run(:keep, params, opts), do: run(:auto_delete, params, opts)

  defp run(:block, params, opts) do
    {fleet_id, token_id, other} = keys(params)

    with {:ok, _block} <- Dms.block_key(fleet_id, token_id, other, opts),
         do: blocks(fleet_id, token_id, opts)
  end

  defp run(:unblock, params, opts) do
    {fleet_id, token_id, other} = keys(params)

    with {:ok, _block} <- Dms.unblock_key(fleet_id, token_id, other, opts),
         do: blocks(fleet_id, token_id, opts)
  end

  defp run(:blocked, %{"fleet_id" => fleet_id, "token_id" => token_id}, opts),
    do: blocks(fleet_id, String.to_integer(token_id), opts)

  defp run(:changes, %{"fleet_id" => fleet_id} = params, opts) do
    with {:ok, page} <- Dms.changes(fleet_id, key_cursors(params), opts[:actor]),
         do: {:ok, changes_json(page)}
  end

  @doc """
  How far each Key's messages have been read, from a body's
  `keys: [{token_id, after_seq}]`, as `Regents.Keyfleet.Dms.changes/3` takes it.
  """
  def key_cursors(%{"keys" => keys}), do: Map.new(keys, &{&1["token_id"], &1["after_seq"]})

  @doc "A page of `Regents.Keyfleet.Dms.changes/3`, as catching up and a sync answer it."
  def changes_json(page),
    do: %{
      messages: Enum.map(page.messages, &message_json/1),
      keys: page.keys,
      has_more: page.has_more
    }

  defp blocks(fleet_id, token_id, opts) do
    with {:ok, blocks} <- Dms.blocks_of_key(fleet_id, token_id, opts),
         do: {:ok, %{blocked: Enum.map(blocks, & &1.blocked_token_id)}}
  end

  # The signed path admits only Key numbers, which fit the database's numbers.
  defp keys(%{"fleet_id" => fleet_id, "token_id" => token_id, "other_token_id" => other}),
    do: {fleet_id, String.to_integer(token_id), String.to_integer(other)}

  defp conversation(fleet_id, token_id, other, opts) do
    case Dms.get_conversation(fleet_id, token_id, other, opts) do
      {:ok, nil} -> :conversation_unknown
      found -> found
    end
  end

  # Where reading on starts: the last message read or, with none, the
  # after_seq sent, never past the last message the Key may see (none before
  # its first), so an after_seq beyond it still reads the next one sent.
  defp cursor([], _after_seq, nil), do: 0
  defp cursor([], after_seq, conversation), do: min(after_seq, conversation.last_seq)
  defp cursor(messages, _after_seq, _conversation), do: List.last(messages).seq

  defp conversation_json(conversation, token_id) do
    %{
      id: conversation.id,
      other_token_id: Dms.other_key(conversation, token_id),
      auto_delete_days: conversation.auto_delete_days,
      last_seq: conversation.last_seq,
      last_message: last_message_json(conversation)
    }
  end

  defp last_message_json(conversation),
    do: %{
      seq: conversation.last_seq,
      body: conversation.last_body,
      from_token_id: conversation.last_from_token_id,
      inserted_at: conversation.last_at
    }

  defp message_json(message) do
    message
    |> Map.take(@message_fields)
    |> Map.put(:via_agent, agent_profile_json(message.via_agent))
  end

  defp agent_profile_json(%Ash.NotLoaded{}), do: nil
  defp agent_profile_json(nil), do: nil

  defp agent_profile_json(profile),
    do: Map.take(profile, [:id, :name, :declared_harness, :current_status])

  defp refuse(:conversation_unknown, _fleet_id, _actor), do: refusal(404, "conversation_unknown")

  # Who holds a Key cannot be read while the fleet's key ownership is not fresh.
  defp refuse({:error, %Ash.Error.Forbidden{}}, fleet_id, actor) do
    if Regents.Keyfleet.Chain.fresh?(fleet_id),
      do: refusal(403, not_holder(actor)),
      else: refusal(503, "ownership_refreshing")
  end

  defp refuse({:error, %Ash.Error.Invalid{errors: errors}}, _fleet_id, _actor) do
    cond do
      Enum.any?(errors, &match?(%UnknownFleetError{}, &1)) ->
        refusal(404, "fleet_unknown")

      unknown = Enum.find(errors, &match?(%KeyUnknownError{}, &1)) ->
        {404, Refusal.key_unknown(unknown.fleet_id, unknown.token_id), nil}

      Enum.any?(errors, &match?(%NoAgentProfileError{}, &1)) ->
        refusal(404, "profile_not_found")

      Enum.any?(errors, &match?(%SameKeyError{}, &1)) ->
        refusal(422, "same_key")

      Enum.any?(errors, &match?(%SendConflictError{}, &1)) ->
        refusal(422, "idempotency_conflict")

      limit = Enum.find(errors, &match?(%SendLimitError{}, &1)) ->
        {429, Refusal.body("dm_limit_reached"), limit.retry_after}

      true ->
        refusal(422, "invalid_dm")
    end
  end

  defp refuse(_error, _fleet_id, _actor), do: refusal(422, "invalid_dm")

  defp refusal(status, code), do: {status, Refusal.body(code), nil}

  # An agent paired with a person, with no Key of its own, is told what keeps
  # it from acting as theirs.
  defp not_holder(%Agent{pairing: :person_not_here}), do: "person_not_here"
  defp not_holder(%Agent{}), do: "not_your_key"
end
