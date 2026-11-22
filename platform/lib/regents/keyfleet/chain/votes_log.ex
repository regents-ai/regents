defmodule Regents.Keyfleet.Chain.VotesLog do
  @moduledoc """
  Reads the logs of a fleet's `KeyfleetVotes` contract into the fields
  `Regents.Keyfleet.Proposals` and `Regents.Keyfleet.Keys` record.

    * `ProposalCreated` is `{:proposal, fields}`, with the exact calls the
      treasury makes if it is carried out. The first second it may be carried
      out is not kept: it is always its execution expiry less 48 hours
      (`Regents.Keyfleet.Proposals.carry_out_from/1`). When it opened is not in it:
      `Regents.Keyfleet.Chain.Logs` takes that from the author key's `Present` log
      just before it.
    * `BallotCast` is `{:ballot, fields}`: keys cast or replaced their
      ballots, all with one choice. A key's latest ballot is the one that
      counts.
    * `ProposalCancelled` is `{:cancellation, fields}` and
      `ProposalExecuted` `{:execution, fields}`.
    * `EditsRestrictionSet` is `{:edits_restriction, fields}`: a carried-out
      proposal restricted a key's workspace edits, or lifted that.
    * `PresenceScheduled`, `Present` and `PresenceCleared` are
      `{:presence, fields}`: a newly sold Key's automatic presence was set to
      start 2 days after its sale, for 48 hours; a Key was renewed, present
      for 48 hours unless it changes hands first; or it changed hands and
      stopped being present.

  `Swept`, which only counts the expired presences it removed, is not read.
  """

  alias RegentChain.Abi
  alias RegentChain.Event

  @created Event.topic0(
             "ProposalCreated(uint256,uint256,address,bytes32,bytes32,uint64,uint64,uint64,uint32,uint48,(address,uint256,bytes)[])"
           )
  @ballot Event.topic0("BallotCast(uint256,address,uint8,uint256[])")
  @cancelled Event.topic0("ProposalCancelled(uint256,address)")
  @executed Event.topic0("ProposalExecuted(uint256,address)")
  @edits_set Event.topic0("EditsRestrictionSet(uint256,bool)")
  @present Event.topic0("Present(uint256,uint64,uint64,uint64)")
  @cleared Event.topic0("PresenceCleared(uint256)")
  @scheduled Event.topic0("PresenceScheduled(uint256,uint64)")

  # The contract's `Choice` numbers (`KeyfleetVotes.Choice` in contracts/src/KeyfleetVotes.sol);
  # `None` is never cast.
  @choices %{1 => :yes, 2 => :no, 3 => :abstain}
  # The words of `ProposalCreated`'s data before its calls.
  @head_words 8

  @doc "The topic0 of every event read here."
  def topics,
    do: [@created, @ballot, @cancelled, @executed, @edits_set, @present, @cleared, @scheduled]

  @doc """
  A log's indexed topics after topic0, as 32-byte words, and its data, as one
  record; `:error` for any other log or a malformed one.
  """
  def decode(@created, [id, author, proposer], data) do
    with {:ok, number} <- number(id),
         {:ok, author_key} <- number(author),
         {:ok, proposer} <- Abi.word(proposer, :address),
         <<head::binary-size(@head_words * 32), calls::binary>> <- data,
         {:ok, fields} <- head(head),
         {:ok, calls} <- calls(calls) do
      {:ok,
       {:proposal,
        Map.merge(fields, %{
          number: number,
          author_key: author_key,
          proposer: proposer,
          calls: calls
        })}}
    else
      _malformed -> :error
    end
  end

  def decode(@ballot, [id, voter], data) do
    with {:ok, number} <- number(id),
         {:ok, voter} <- Abi.word(voter, :address),
         {:ok, [choice, [_ | _] = token_ids]} <-
           Abi.decode(data, [{:uint, 8}, {:array, {:uint, 63}}]),
         {:ok, choice} <- Map.fetch(@choices, choice),
         true <- Enum.all?(token_ids, &(&1 > 0)) do
      {:ok,
       {:ballot, %{proposal_number: number, voter: voter, choice: choice, token_ids: token_ids}}}
    else
      _malformed -> :error
    end
  end

  def decode(@cancelled, [id, by], data) do
    with {:ok, number} <- number(id),
         {:ok, by} <- Abi.word(by, :address),
         {:ok, []} <- Abi.decode(data, []) do
      {:ok, {:cancellation, %{proposal_number: number, cancelled_by: by}}}
    else
      _malformed -> :error
    end
  end

  def decode(@executed, [id, executor], data) do
    with {:ok, number} <- number(id),
         {:ok, executor} <- Abi.word(executor, :address),
         {:ok, []} <- Abi.decode(data, []) do
      {:ok, {:execution, %{proposal_number: number, executor: executor}}}
    else
      _malformed -> :error
    end
  end

  def decode(@edits_set, [token], data) do
    with {:ok, token_id} <- number(token),
         {:ok, [restricted]} <- Abi.decode(data, [:bool]) do
      {:ok, {:edits_restriction, %{token_id: token_id, restricted: restricted}}}
    else
      _malformed -> :error
    end
  end

  def decode(@present, [token], data) do
    with {:ok, token_id} <- number(token),
         {:ok, [at, _block_number, epoch]} <-
           Abi.decode(data, [{:uint, 63}, {:uint, 63}, {:uint, 63}]),
         true <- epoch > 0,
         {:ok, at} <- DateTime.from_unix(at) do
      {:ok, {:presence, %{kind: :present, token_id: token_id, at: at, ownership_epoch: epoch}}}
    else
      _malformed -> :error
    end
  end

  def decode(@cleared, [token], data) do
    with {:ok, token_id} <- number(token),
         {:ok, []} <- Abi.decode(data, []) do
      {:ok, {:presence, %{kind: :cleared, token_id: token_id, at: nil, ownership_epoch: nil}}}
    else
      _malformed -> :error
    end
  end

  def decode(@scheduled, [token], data) do
    with {:ok, token_id} <- number(token),
         {:ok, [starts_at]} <- Abi.decode(data, [{:uint, 63}]),
         {:ok, starts_at} <- DateTime.from_unix(starts_at) do
      {:ok,
       {:presence, %{kind: :scheduled, token_id: token_id, at: starts_at, ownership_epoch: nil}}}
    else
      _malformed -> :error
    end
  end

  def decode(_topic0, _topics, _data), do: :error

  # The data's words before its calls, the last of which must point just past
  # them, where the calls begin.
  defp head(head) do
    with {:ok,
          [
            proposal_hash,
            content_hash,
            closes_at,
            _executable_at,
            expiry,
            e0,
            open_revision,
            offset
          ]} <-
           words(head, [
             :bytes32,
             :bytes32,
             {:uint, 63},
             {:uint, 63},
             {:uint, 63},
             {:uint, 32},
             {:uint, 48},
             {:uint, 256}
           ]),
         true <- offset == @head_words * 32,
         {:ok, closes_at} <- DateTime.from_unix(closes_at),
         {:ok, expiry} <- DateTime.from_unix(expiry) do
      {:ok,
       %{
         proposal_hash: proposal_hash,
         content_hash: content_hash,
         closes_at: closes_at,
         execution_expiry: expiry,
         opening_count: e0,
         open_revision: open_revision
       }}
    else
      _malformed -> :error
    end
  end

  defp words(bytes, types) do
    for(<<word::binary-size(32) <- bytes>>, do: word)
    |> Enum.zip(types)
    |> each_ok(fn {word, type} -> Abi.word(word, type) end)
  end

  # `(address target, uint256 value, bytes data)[]` exactly as the contract
  # encodes it: its length, then the offset of each call, each call placed
  # right after the one before it, and nothing left over. Each call is read
  # strictly by `RegentChain.Abi.decode/2`.
  defp calls(<<0::256>>), do: {:ok, []}

  defp calls(<<length::256, rest::binary>>)
       when length > 0 and length <= div(byte_size(rest), 32 * 4) do
    <<offsets::binary-size(32 * ^length), _calls::binary>> = rest
    starts = for <<offset::256 <- offsets>>, do: offset
    ends = Enum.drop(starts, 1) ++ [byte_size(rest)]

    with [first | _] <- starts,
         true <- first == 32 * length,
         true <- Enum.all?(Enum.zip(starts, ends), fn {from, to} -> from < to end) do
      starts
      |> Enum.zip(ends)
      |> each_ok(fn {from, to} -> call(binary_part(rest, from, to - from)) end)
    else
      _malformed -> :error
    end
  end

  defp calls(_malformed), do: :error

  defp call(bytes) do
    case Abi.decode(bytes, [:address, {:uint, 256}, :bytes]) do
      {:ok, [target, value, data]} ->
        {:ok, %{target: target, value: value, data: "0x" <> Base.encode16(data, case: :lower)}}

      :error ->
        :error
    end
  end

  # `fun` applied to each of `items`, in order, while each answers `{:ok, value}`.
  defp each_ok(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, values} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, :error}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end)
  end

  defp number(topic) do
    case Abi.word(topic, {:uint, 63}) do
      {:ok, number} when number > 0 -> {:ok, number}
      _malformed -> :error
    end
  end
end
