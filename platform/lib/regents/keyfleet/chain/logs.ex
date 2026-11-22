defmodule Regents.Keyfleet.Chain.Logs do
  @moduledoc """
  Turns the raw logs of one stretch of a fleet's blocks into the records the
  reader makes, in the order the chain made them.

  Each log is sent, by its contract and topic0, to
  `Regents.Keyfleet.Chain.OwnershipLog` or `Regents.Keyfleet.Chain.RevealLog`, for the Key
  collection every fleet shares, `Regents.Keyfleet.Chain.ShardsLog`, for the shard
  record every fleet shares, `Regents.Keyfleet.Chain.VotesLog`, for the fleet's vote
  contract, or `Regents.Keyfleet.Chain.MoneyLog`, for its manager, treasury and
  reward ledger and the REGENT buyer every fleet shares, and carries its fleet
  and its place on the chain. The buyer is the one the fleet's manager names
  (`REGENT_BUYER()`), which the reader reads with each pass.

  The chain names a Key by its token id in the collection; each record names
  it by its number in the fleet (`Regents.Keyfleet.Fleets.Fleet.key_number/2`). A log
  of the shared contracts about another fleet's Key is left out. A proposal
  takes the time it opened from the renewal of its author Key logged just
  before it, in the same transaction. A log the node lists twice is read
  once. One log that cannot be read, a log of the fleet's own contracts about
  another fleet's Key, two different logs in one place, or a proposal without
  its author's renewal refuses the whole stretch, and the reason names the
  log.
  """

  alias RegentChain.Abi
  alias Regents.Keyfleet.Chain.MoneyLog
  alias Regents.Keyfleet.Chain.OwnershipLog
  alias Regents.Keyfleet.Chain.RevealLog
  alias Regents.Keyfleet.Chain.ShardsLog
  alias Regents.Keyfleet.Chain.VotesLog
  alias Regents.Keyfleet.Fleets.Fleet

  @doc "The contracts whose logs the reader asks for, for `fleet` and its REGENT buyer `buyer`."
  def addresses(fleet, buyer),
    do: [
      fleet.keys_address,
      fleet.manager_address,
      fleet.votes_address,
      fleet.shards_address,
      fleet.treasury_address,
      fleet.rewards_address,
      buyer
    ]

  @doc "The topic0 of every event the reader asks for."
  def topics,
    do:
      Enum.concat([
        [OwnershipLog.topic(), RevealLog.topic(), RevealLog.expired_topic()],
        MoneyLog.fleet_topics(),
        VotesLog.topics(),
        ShardsLog.topics(),
        MoneyLog.treasury_topics(),
        MoneyLog.rewards_topics(),
        MoneyLog.buyer_topics()
      ])

  @doc """
  The records in `logs`, read from blocks `from..to` of `fleet`, whose REGENT
  buyer is `buyer`, in (block,
  log index) order. Otherwise `{:error, reason}`, where the reason names the
  transaction hash and log index of the log refused:

    * `{:unreadable_log, transaction_hash, log_index}`: the log is outside
      that stretch, is not from the fleet's contracts, is not exactly as
      they emit it, or is a log of the fleet's own contracts about another
      fleet's Key.
    * `{:conflicting_logs, transaction_hash, log_index}`: two different logs
      claim the same place.
    * `{:opening_missing, transaction_hash, log_index}`: a proposal does not
      follow its author key's renewal in the same transaction.
  """
  def decode(logs, fleet, buyer, from, to) do
    with {:ok, records} <- decode_each(logs, {fleet, buyer}, from..to//1, []),
         {:ok, records} <- distinct(records),
         do: records |> Enum.sort_by(&position/1) |> join([])
  end

  @doc """
  Whether `records` can be made after the fleet's highest recorded proposal
  number, `highest`: each new proposal must be the next number, and each vote
  ballot, cancellation and execution must name a proposal recorded by then. A
  proposal at or below the highest takes a number already recorded, and
  recording keeps the proposal saved first under it. Every other record names
  no proposal.
  """
  def in_sequence(records, highest) do
    Enum.reduce_while(records, highest, fn
      {:proposal, %{number: number}}, top when number <= top ->
        {:cont, top}

      {:proposal, %{number: number}}, top when number == top + 1 ->
        {:cont, number}

      {:proposal, proposal}, _top ->
        {:halt, {:error, {:proposal_number_skipped, proposal.block_number}}}

      {_type, %{proposal_number: number}}, top when number <= top ->
        {:cont, top}

      {_type, %{proposal_number: _number} = record}, _top ->
        {:halt, {:error, {:proposal_not_recorded, record.block_number}}}

      {_type, _record}, top ->
        {:cont, top}
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      _highest -> :ok
    end
  end

  defp decode_each([], _contracts, _blocks, records), do: {:ok, Enum.reverse(records)}

  defp decode_each([log | logs], contracts, blocks, records) do
    case decode_one(log, contracts, blocks) do
      {:ok, record} ->
        decode_each(logs, contracts, blocks, [record | records])

      :other_fleet ->
        decode_each(logs, contracts, blocks, records)

      :error ->
        {:error, {:unreadable_log, as_given(log, "transactionHash"), as_given(log, "logIndex")}}
    end
  end

  defp as_given(%{} = log, field), do: log[field]
  defp as_given(_log, _field), do: nil

  defp decode_one(
         %{
           "address" => address,
           "topics" => [topic0 | topics],
           "data" => data,
           "blockNumber" => block_number,
           "blockHash" => block_hash,
           "transactionHash" => transaction_hash,
           "logIndex" => log_index
         },
         {fleet, buyer},
         blocks
       )
       when is_binary(address) and is_binary(topic0) do
    with {:ok, block_number} <- Abi.quantity(block_number),
         true <- block_number in blocks,
         {:ok, block_hash} <- Abi.hash(block_hash),
         {:ok, transaction_hash} <- Abi.hash(transaction_hash),
         {:ok, log_index} <- Abi.quantity(log_index),
         {:ok, words} <- words(topics, []),
         {:ok, data} <- Abi.bytes(data),
         {:ok, {type, fields}} <-
           read(fleet, buyer, String.downcase(address), topic0, words, data) do
      {:ok,
       {type,
        Map.merge(fields, %{
          fleet_id: fleet.id,
          block_number: block_number,
          block_hash: block_hash,
          transaction_hash: transaction_hash,
          log_index: log_index
        })}}
    else
      :other_fleet -> :other_fleet
      _malformed -> :error
    end
  end

  defp decode_one(_log, _contracts, _blocks), do: :error

  # The log's record with its Keys named by their numbers in the fleet. A
  # log of a shared contract about another fleet's Key, or of the buyer about
  # another fleet's piece, is `:other_fleet`.
  defp read(fleet, buyer, buyer, topic0, words, data),
    do: MoneyLog.decode_bought(fleet, String.downcase(topic0), words, data)

  defp read(fleet, _buyer, address, topic0, words, data) do
    with {:ok, {owner, {type, fields}}} <-
           route(fleet, address, String.downcase(topic0), words, data) do
      case local(fields, fleet) do
        {:ok, fields} -> {:ok, {type, fields}}
        :foreign when owner == :shared -> :other_fleet
        :foreign -> :error
      end
    end
  end

  defp local(fields, fleet) do
    Enum.reduce_while([:token_id, :author_key, :token_ids], {:ok, fields}, fn field, {:ok, acc} ->
      case local_field(Map.get(acc, field), fleet) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        :foreign -> {:halt, :foreign}
      end
    end)
  end

  defp local_field(nil, _fleet), do: {:ok, nil}

  defp local_field(token_ids, fleet) when is_list(token_ids) do
    Enum.reduce_while(token_ids, {:ok, []}, fn token_id, {:ok, numbers} ->
      case Fleet.key_number(fleet, token_id) do
        {:ok, number} -> {:cont, {:ok, [number | numbers]}}
        :foreign -> {:halt, :foreign}
      end
    end)
    |> then(fn
      {:ok, numbers} -> {:ok, Enum.reverse(numbers)}
      :foreign -> :foreign
    end)
  end

  defp local_field(token_id, fleet), do: Fleet.key_number(fleet, token_id)

  defp route(%{keys_address: address}, address, topic0, words, data) do
    record =
      with :error <- OwnershipLog.decode(topic0, words, data),
           do: RevealLog.decode(topic0, words, data)

    owned_by(:shared, record)
  end

  defp route(%{shards_address: address}, address, topic0, words, data),
    do: owned_by(:shared, ShardsLog.decode(topic0, words, data))

  defp route(%{manager_address: address}, address, topic0, words, data),
    do: owned_by(:own, MoneyLog.decode(:fleet, topic0, words, data))

  defp route(%{votes_address: address}, address, topic0, words, data),
    do: owned_by(:own, VotesLog.decode(topic0, words, data))

  defp route(%{treasury_address: address}, address, topic0, words, data),
    do: owned_by(:own, MoneyLog.decode(:treasury, topic0, words, data))

  defp route(%{rewards_address: address}, address, topic0, words, data),
    do: owned_by(:own, MoneyLog.decode(:rewards, topic0, words, data))

  defp route(_fleet, _address, _topic0, _words, _data), do: :error

  defp owned_by(owner, {:ok, record}), do: {:ok, {owner, record}}
  defp owned_by(_owner, :error), do: :error

  defp words([], words), do: {:ok, Enum.reverse(words)}

  defp words([topic | topics], words) do
    case Abi.bytes(topic) do
      {:ok, <<word::binary-size(32)>>} -> words(topics, [word | words])
      _malformed -> :error
    end
  end

  defp position({_type, record}), do: {record.block_number, record.log_index}
  defp event({_type, record}), do: {record.transaction_hash, record.log_index}

  # The same log listed twice is read once. Two different logs in one block at
  # one index, or with one transaction hash and index, are not one chain.
  defp distinct(records) do
    records = Enum.uniq(records)

    with :ok <- one_each(records, &position/1),
         :ok <- one_each(records, &event/1),
         do: {:ok, records}
  end

  defp one_each(records, place) do
    records
    |> Enum.group_by(place)
    |> Enum.find_value(:ok, fn
      {_place, [{_type, record}, _other | _rest]} ->
        {:error, {:conflicting_logs, record.transaction_hash, record.log_index}}

      {_place, [_one]} ->
        nil
    end)
  end

  # A proposal opens at the time its author key is renewed, which the
  # contract logs just before the proposal, in the same transaction.
  defp join([], records), do: {:ok, Enum.reverse(records)}

  defp join(
         [
           {:presence, %{kind: :present, token_id: key, at: at, transaction_hash: transaction}} =
             renewal,
           {:proposal, %{author_key: key, transaction_hash: transaction} = proposal} | rest
         ],
         records
       ),
       do: join(rest, [{:proposal, Map.put(proposal, :opened_at, at)}, renewal | records])

  defp join([{:proposal, proposal} | _rest], _records),
    do: {:error, {:opening_missing, proposal.transaction_hash, proposal.log_index}}

  defp join([record | rest], records), do: join(rest, [record | records])
end
