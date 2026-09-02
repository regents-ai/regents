defmodule AshPlatform.WalletActions.Abi do
  @moduledoc false

  alias AshPlatform.WalletActions.Address

  @manifest_path Path.expand("../../../contracts/base-mainnet.json", __DIR__)
  @abi_path Path.expand("../../../contracts/abi/regent-revenue-staking.json", __DIR__)
  @multicall3_abi_path Path.expand("../../../contracts/abi/multicall3.json", __DIR__)
  @external_resource @manifest_path
  @external_resource @abi_path
  @external_resource @multicall3_abi_path

  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @abi @abi_path |> File.read!() |> Jason.decode!()
  @multicall3_abi @multicall3_abi_path |> File.read!() |> Jason.decode!()
  @staking get_in(@manifest, ["contracts", "regent_revenue_staking"])
  @actions Map.new(@staking["prepared_actions"], &{&1["id"], &1})
  @reads Map.new(@staking["reads"], &{&1["id"], &1})

  @address_bound Integer.pow(2, 160)
  @word_bytes 32

  # The evidence manifest stays byte-for-byte frozen, so the one read it does not
  # carry is encoded here against the pinned ABI's own declaration of it.
  @supply_denominator_signature "revenueShareSupplyDenominator()"
  @supply_denominator_selector "0xe3961f2a"
  @total_usdc_received_signature "totalUsdcReceived()"
  @total_usdc_received_selector "0xcf51bfdd"
  @emission_apr_signature "emissionAprBps()"
  @emission_apr_selector "0x8ba7fda0"

  # `totalSupply()` belongs to the REGENT token, not to this contract, so it is
  # not proved against the staking ABI below. The same selector is recorded for
  # the Regents Club token in contracts/chain-contracts.yaml.
  @erc20_total_supply_signature "totalSupply()"
  @erc20_total_supply_selector "0x18160ddd"

  # Multicall3 is the canonical read aggregator, deployed at the same address on
  # every chain it reaches, Base included. It is never a send target: the only
  # thing this codebase asks it for is one `eth_call` that returns several reads
  # of one block together, and its identity is proved against the runtime code
  # hash below before any answer of its is believed.
  #
  # The evidence manifest stays byte-for-byte frozen, so the identity lives here
  # as module constants, exactly as the reads it does not carry do. Recorded at
  # admission from a live read-only `eth_getCode` at Base block 50767245
  # (0x164fba1ff76fe80adef28ad9780776f5cf56331279d7b852b4c1cfb61e26a0e6,
  # requireCanonical); see artifacts/web-ops-2026-09-01/multicall3-admission-2026-09-02.md.
  @multicall3_address "0xcA11bde05977b3631167028862bE2a173976CA11"
  @multicall3_runtime_keccak256 "0xd5c15df687b16f2ff992fc8d767b4216323184a2bbc6ee2f9c398c318e770891"
  @multicall3_runtime_sha256 "2756d7c52baee85cacb504f6ee1df7aad6809ac8d94a4a111d76991f90d36d6e"
  @multicall3_runtime_bytes 3808
  @aggregate3_signature "aggregate3((address,bool,bytes)[])"
  @aggregate3_selector "0x82ad56cb"

  @event_signatures %{
    approval: "Approval(address,address,uint256)",
    stake_updated: "StakeUpdated(address,uint256,uint256)",
    usdc_reward_claimed: "USDCRewardClaimed(address,uint256,address)",
    reward_token_claimed: "RewardTokenClaimed(address,uint256,address)",
    reward_token_compounded: "RewardTokenCompounded(address,uint256,uint256,uint256)",
    usdc_revenue_deposited:
      "USDCRevenueDeposited(uint256,uint256,uint256,uint8,address,bytes32,bytes32)"
  }

  @usdc_revenue_indexed 3
  @usdc_revenue_data_words 4

  # A derived selector or topic is only proof if the deployed ABI really declares
  # the signature it was derived from. `Approval` belongs to the REGENT token, not
  # to this contract, so only the staking events are proved against this ABI.
  # A module cannot call its own checker while it is being compiled, so the proof
  # runs the moment it is.
  @after_compile __MODULE__
  @declarations [
    {"function", @supply_denominator_signature},
    {"function", @total_usdc_received_signature},
    {"function", @emission_apr_signature}
    | for({id, signature} <- @event_signatures, id != :approval, do: {"event", signature})
  ]

  @doc false
  def __after_compile__(_env, _bytecode) do
    Enum.each(@declarations, fn {kind, signature} -> declared!(@abi, kind, signature) end)
    declared!(@multicall3_abi, "function", @aggregate3_signature)
  end

  @doc "Raises unless `abi` declares exactly this function or event signature."
  def declared!(abi, kind, signature) do
    [name] = Regex.run(~r/^(\w+)\(/, signature, capture: :all_but_first)

    Enum.any?(abi, fn
      %{"type" => ^kind, "name" => ^name, "inputs" => inputs} ->
        "#{name}(#{Enum.map_join(inputs, ",", &canonical_type/1)})" == signature

      _entry ->
        false
    end) || raise "pinned ABI is missing #{signature}"
  end

  # A tuple's ABI type is its component list, so a struct argument is proved
  # against the exact signature its selector was derived from rather than
  # against the placeholder word `tuple`.
  defp canonical_type(%{"type" => "tuple" <> suffix, "components" => components}),
    do: "(#{Enum.map_join(components, ",", &canonical_type/1)})#{suffix}"

  defp canonical_type(%{"type" => type}), do: type

  def staking_address, do: @staking["address"]
  def stake_token_address, do: get_in(@staking, ["onchain_constants", "stake_token"])
  def usdc_address, do: get_in(@staking, ["onchain_constants", "usdc"])
  def encode_supply_denominator, do: @supply_denominator_selector
  def encode_total_usdc_received, do: @total_usdc_received_selector
  def encode_emission_apr_bps, do: @emission_apr_selector
  def encode_erc20_total_supply, do: @erc20_total_supply_selector
  def supply_denominator_signature, do: @supply_denominator_signature
  def total_usdc_received_signature, do: @total_usdc_received_signature
  def erc20_total_supply_signature, do: @erc20_total_supply_signature

  def multicall3_address, do: @multicall3_address
  def multicall3_runtime_keccak256, do: @multicall3_runtime_keccak256
  def multicall3_runtime_sha256, do: @multicall3_runtime_sha256
  def multicall3_runtime_bytes, do: @multicall3_runtime_bytes
  def aggregate3_signature, do: @aggregate3_signature
  def aggregate3_selector, do: @aggregate3_selector

  @doc """
  Calldata for one Multicall3 `aggregate3` carrying exactly these sub-calls.

  `allowFailure` is `false` on every sub-call and is not a caller's choice: a
  sub-call that reverts reverts the whole aggregate, so a page never renders a
  reading assembled from some answers and some silence. Under Multicall3 the
  `msg.sender` each sub-call sees is Multicall3 itself, so every sub-call here
  names the account it reads about in its own arguments.

  `calls` is a list of `{target, calldata}` pairs, both `0x`-prefixed hex.
  """
  def encode_aggregate3(calls) when is_list(calls) and calls != [] do
    bodies = Enum.map(calls, &encode_call3/1)
    heads_bytes = length(bodies) * @word_bytes

    {heads, _next} =
      Enum.map_reduce(bodies, heads_bytes, fn body, offset ->
        {word(offset), offset + hex_bytes(body)}
      end)

    @aggregate3_selector <>
      word(@word_bytes) <> word(length(bodies)) <> Enum.join(heads) <> Enum.join(bodies)
  end

  @doc """
  The `bytes` each sub-call of one `aggregate3` returned, in the order asked.

  Every offset the response declares is checked against the payload it points
  into before a single byte is read through it, and a sub-call reporting
  anything other than success is refused: `allowFailure` was `false`, so an
  unsuccessful entry is a contradiction rather than a value to interpret.
  """
  def decode_aggregate3("0x" <> hex, count) when is_integer(count) and count > 0 do
    with {:ok, payload} <- Base.decode16(hex, case: :mixed),
         {:ok, array_offset} <- word_at(payload, 0),
         {:ok, array} <- region(payload, array_offset),
         {:ok, ^count} <- word_at(array, 0),
         {:ok, entries} <- decode_entries(binary_part(array, 32, byte_size(array) - 32), count) do
      {:ok, entries}
    else
      _malformed -> :error
    end
  end

  def decode_aggregate3(_value, _count), do: :error

  # Each entry is bounded by the one that follows it before anything inside it
  # is read, so a declared width can never reach into the next entry's bytes or
  # into trailing rubbish. Canonical encoding lays the entries out in order, so
  # offsets that are not strictly ascending are refused rather than reordered.
  defp decode_entries(body, count) do
    with {:ok, offsets} <- entry_offsets(body, count),
         true <- ascending_entries?(offsets, count * @word_bytes, byte_size(body)) do
      offsets
      |> Enum.zip(tl(offsets) ++ [byte_size(body)])
      |> Enum.map(fn {offset, bound} -> binary_part(body, offset, bound - offset) end)
      |> collect(&decode_entry/1)
    else
      _malformed -> :error
    end
  end

  # Every element decodes, or none of them does.
  defp collect(items, decoder) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, decoded} ->
      case decoder.(item) do
        {:ok, value} -> {:cont, {:ok, [value | decoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      :error -> :error
    end
  end

  defp entry_offsets(body, count),
    do: collect(0..(count - 1)//1, &word_at(body, &1 * @word_bytes))

  # An entry may not start inside the head words that hold the offsets, may not
  # start where another one does or before it, and may not start outside the
  # payload; every start is word-aligned. One strictly ascending rule says the
  # middle of that, and because it holds, the first offset is the lowest and the
  # last the highest, so the two bounds either side of it mean what they say.
  defp ascending_entries?(offsets, heads_bytes, size) do
    Enum.all?(offsets, &(rem(&1, @word_bytes) == 0)) and
      List.first(offsets) >= heads_bytes and
      List.last(offsets) + 2 * @word_bytes <= size and
      strictly_ascending?(offsets)
  end

  defp strictly_ascending?(offsets),
    do:
      offsets
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [start, next] -> next > start end)

  # `(bool success, bytes returnData)`, read only from an entry already bounded
  # to its own width. `allowFailure` was false, so anything other than success
  # is a contradiction rather than a value to interpret, and the payload has to
  # fill its entry exactly.
  defp decode_entry(entry) do
    with {:ok, 1} <- word_at(entry, 0),
         {:ok, data_offset} <- word_at(entry, @word_bytes),
         true <- data_offset >= 2 * @word_bytes,
         {:ok, data} <- region(entry, data_offset),
         {:ok, size} <- word_at(data, 0),
         true <- byte_size(data) - @word_bytes == padded(size) do
      {:ok, "0x" <> Base.encode16(binary_part(data, @word_bytes, size), case: :lower)}
    else
      _malformed -> :error
    end
  end

  # An offset is only usable when it is word-aligned and leaves at least one
  # whole word inside the payload it points into.
  defp region(payload, offset)
       when is_integer(offset) and rem(offset, @word_bytes) == 0 and
              offset + @word_bytes <= byte_size(payload),
       do: {:ok, binary_part(payload, offset, byte_size(payload) - offset)}

  defp region(_payload, _offset), do: :error

  defp word_at(payload, at) when at >= 0 and at + @word_bytes <= byte_size(payload),
    do: {:ok, :binary.decode_unsigned(binary_part(payload, at, @word_bytes))}

  defp word_at(_payload, _at), do: :error

  defp padded(size), do: div(size + @word_bytes - 1, @word_bytes) * @word_bytes

  defp encode_call3({target, "0x" <> data}) when rem(byte_size(data), 2) == 0 do
    encode_static("address", target) <>
      word(0) <>
      word(3 * @word_bytes) <>
      word(div(byte_size(data), 2)) <> pad_trailing(String.downcase(data))
  end

  defp hex_bytes(hex), do: div(byte_size(hex), 2)

  defp pad_trailing(""), do: ""

  defp pad_trailing(hex),
    do: String.pad_trailing(hex, div(byte_size(hex) + 63, 64) * 64, "0")

  defp word(value) when is_integer(value) and value >= 0,
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")

  def encode_action(id, arguments) when is_binary(id) and is_list(arguments) do
    entry = Map.fetch!(@actions, id)
    encode(entry, arguments)
  end

  def encode_read(id, arguments \\ []) when is_binary(id) and is_list(arguments) do
    entry = Map.fetch!(@reads, id)
    encode(entry, arguments)
  end

  def encode_erc20(id, arguments) when id in ["approve", "balance_of", "allowance"] do
    interface = Map.fetch!(@manifest["standard_interfaces"], "erc20")
    entry = Enum.find(interface, &(&1["id"] == id)) || raise "missing ERC-20 ABI entry #{id}"
    encode_standard(entry, arguments)
  end

  @doc "Ethereum Keccak-256 of an exact event signature, which is its `topic0`."
  def topic0(signature),
    do: "0x" <> Base.encode16(:jose_jwa_sha3.keccak(1088, 512, signature, 1, 32), case: :lower)

  def event_signature(id), do: Map.fetch!(@event_signatures, id)
  def event_topic(id), do: id |> event_signature() |> topic0()

  @doc """
  The one log in this receipt that is exactly this event.

  Emitter, `topic0`, indexed count and data width all have to be exact, and the
  event has to appear exactly once: absent and duplicated are both `:error`,
  while logs belonging to other events are ignored.
  """
  def one_event(logs, topic, emitter, indexed_count, data_words) when is_list(logs) do
    case Enum.filter(logs, &emitted?(&1, topic, emitter)) do
      [log] -> decode_event(log, indexed_count, data_words)
      _absent_or_duplicated -> :error
    end
  end

  def one_event(_logs, _topic, _emitter, _indexed_count, _data_words), do: :error

  @doc """
  The USDC every `USDCRevenueDeposited` in `logs` recorded, added together.

  `amountReceived` is the first of the event's four unindexed words and is the
  exact figure the contract adds to `totalUsdcReceived`, so the logs of a block
  range add up to what was registered over that range. Both recorded sources, a
  direct deposit and a redeposited surplus, raise that total and are counted
  here.

  A log this contract did not emit, or one carrying any other shape, fails the
  whole sum: a figure assembled from the logs that happened to parse would
  understate what the contract registered.
  """
  def usdc_revenue_received(logs) when is_list(logs) do
    topic = event_topic(:usdc_revenue_deposited)

    Enum.reduce_while(logs, {:ok, 0}, fn log, {:ok, total} ->
      with true <- emitted?(log, topic, staking_address()),
           {:ok, {_indexed, [received | _rest]}} <-
             decode_event(log, @usdc_revenue_indexed, @usdc_revenue_data_words) do
        {:cont, {:ok, total + received}}
      else
        _contradiction -> {:halt, :error}
      end
    end)
  end

  def usdc_revenue_received(_logs), do: :error

  @doc "The address a 32-byte word names, which requires its leading twelve bytes to be zero."
  def word_address(value) when is_integer(value) and value > 0 and value < @address_bound,
    do:
      {:ok,
       "0x" <>
         (value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(40, "0"))}

  def word_address(_value), do: :error

  @doc "The exact ERC-20 approval this transaction had to record."
  def approval_recorded?(logs, token, owner, spender, value) do
    with {:ok, {[owner_word, spender_word], [^value]}} <-
           one_event(logs, event_topic(:approval), token, 2, 1),
         {:ok, ^owner} <- word_address(owner_word),
         {:ok, ^spender} <- word_address(spender_word) do
      true
    else
      _contradiction -> false
    end
  end

  @doc """
  The post-action stake fact a Stake or Unstake had to record for `account`.

  There is no previous-stake field, and the global total is never this account's
  balance: only their relationship is checked here.
  """
  def stake_updated?(logs, account), do: match?({:ok, _post_action}, stake_updated(logs, account))

  @doc "The compounded reward plus its companion `StakeUpdated` carrying identical post-action fields."
  def reward_compounded?(logs, account) do
    with {:ok, {[account_word], [amount, new_balance, total]}} <-
           one_event(logs, event_topic(:reward_token_compounded), staking_address(), 1, 3),
         {:ok, ^account} <- word_address(account_word),
         true <- amount > 0,
         {:ok, [^new_balance, ^total]} <- stake_updated(logs, account) do
      true
    else
      _contradiction -> false
    end
  end

  @doc "A positive reward claim whose account and envelope-pinned recipient are both the signer."
  def reward_claimed?(logs, id, account)
      when id in [:usdc_reward_claimed, :reward_token_claimed] do
    with {:ok, {[account_word], [amount, recipient_word]}} <-
           one_event(logs, event_topic(id), staking_address(), 1, 2),
         {:ok, ^account} <- word_address(account_word),
         {:ok, ^account} <- word_address(recipient_word) do
      amount > 0
    else
      _contradiction -> false
    end
  end

  defp stake_updated(logs, account) do
    with {:ok, {[account_word], [new_balance, total] = post_action}} <-
           one_event(logs, event_topic(:stake_updated), staking_address(), 1, 2),
         {:ok, ^account} <- word_address(account_word),
         true <- new_balance <= total do
      {:ok, post_action}
    else
      _contradiction -> :error
    end
  end

  defp emitted?(%{"address" => address, "topics" => [topic | _indexed]}, expected, emitter)
       when is_binary(topic),
       do: String.downcase(topic) == expected and Address.equal?(address, emitter)

  defp emitted?(_log, _expected, _emitter), do: false

  defp decode_event(%{"topics" => [_topic | indexed], "data" => "0x" <> data}, count, words)
       when length(indexed) == count and byte_size(data) == words * 64 do
    {:ok,
     {Enum.map(indexed, &topic_word!/1), for(<<word::binary-size(64) <- data>>, do: word!(word))}}
  rescue
    _malformed -> :error
  end

  defp decode_event(_log, _count, _words), do: :error

  defp topic_word!("0x" <> hex) when byte_size(hex) == 64, do: word!(hex)

  defp word!(hex) do
    {:ok, bytes} = Base.decode16(hex, case: :mixed)
    :binary.decode_unsigned(bytes)
  end

  defp encode(entry, arguments) do
    function = function_for_signature!(entry["signature"])
    inputs = function["inputs"] || []

    encode_inputs(entry, inputs, arguments)
  end

  defp encode_standard(entry, arguments) do
    [encoded_types] = Regex.run(~r/^\w+\((.*)\)$/, entry["signature"], capture: :all_but_first)

    inputs =
      if encoded_types == "",
        do: [],
        else: Enum.map(String.split(encoded_types, ","), &%{"type" => &1})

    encode_inputs(entry, inputs, arguments)
  end

  defp encode_inputs(entry, inputs, arguments) do
    if length(inputs) != length(arguments) do
      raise ArgumentError, "ABI argument count does not match #{entry["signature"]}"
    end

    encoded =
      inputs
      |> Enum.zip(arguments)
      |> Enum.map_join(fn {input, argument} -> encode_static(input["type"], argument) end)

    String.downcase(entry["selector"] <> encoded)
  end

  defp function_for_signature!(signature) do
    Enum.find(@abi, fn
      %{"type" => "function", "name" => name, "inputs" => inputs} ->
        "#{name}(#{Enum.map_join(inputs, ",", & &1["type"])})" == signature

      _ ->
        false
    end) || raise "pinned staking ABI is missing #{signature}"
  end

  defp encode_static("address", address) do
    normalized = normalize_address!(address)
    normalized |> String.trim_leading("0x") |> String.pad_leading(64, "0")
  end

  defp encode_static("uint256", value) when is_integer(value) and value >= 0 do
    value |> Integer.to_string(16) |> String.pad_leading(64, "0")
  end

  defp encode_static(type, _value), do: raise(ArgumentError, "unsupported ABI input #{type}")

  def normalize_address!(address) do
    case Address.normalize(address) do
      {:ok, normalized} -> normalized
      :error -> raise ArgumentError, "wallet address is invalid"
    end
  end
end
