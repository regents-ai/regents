defmodule AshPlatform.WalletActions.Abi do
  @moduledoc false

  alias AshPlatform.WalletActions.Address

  @manifest_path Path.expand("../../../contracts/base-mainnet.json", __DIR__)
  @abi_path Path.expand("../../../contracts/abi/regent-revenue-staking.json", __DIR__)
  @external_resource @manifest_path
  @external_resource @abi_path

  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @abi @abi_path |> File.read!() |> Jason.decode!()
  @staking get_in(@manifest, ["contracts", "regent_revenue_staking"])
  @actions Map.new(@staking["prepared_actions"], &{&1["id"], &1})
  @reads Map.new(@staking["reads"], &{&1["id"], &1})

  @address_bound Integer.pow(2, 160)

  # The evidence manifest stays byte-for-byte frozen, so the one read it does not
  # carry is encoded here against the pinned ABI's own declaration of it.
  @supply_denominator_signature "revenueShareSupplyDenominator()"
  @supply_denominator_selector "0xe3961f2a"
  @available_regent_signature "availableRegentRewardInventory()"
  @available_regent_selector "0xe2cfe6b9"
  @reserved_usdc_signature "reservedUsdc()"
  @reserved_usdc_selector "0x017a2078"
  @emission_apr_signature "emissionAprBps()"
  @emission_apr_selector "0x8ba7fda0"

  @event_signatures %{
    approval: "Approval(address,address,uint256)",
    stake_updated: "StakeUpdated(address,uint256,uint256)",
    usdc_reward_claimed: "USDCRewardClaimed(address,uint256,address)",
    reward_token_claimed: "RewardTokenClaimed(address,uint256,address)",
    reward_token_compounded: "RewardTokenCompounded(address,uint256,uint256,uint256)"
  }

  # A derived selector or topic is only proof if the deployed ABI really declares
  # the signature it was derived from. `Approval` belongs to the REGENT token, not
  # to this contract, so only the staking events are proved against this ABI.
  # A module cannot call its own checker while it is being compiled, so the proof
  # runs the moment it is.
  @after_compile __MODULE__
  @declarations [
    {"function", @supply_denominator_signature},
    {"function", @available_regent_signature},
    {"function", @reserved_usdc_signature},
    {"function", @emission_apr_signature}
    | for({id, signature} <- @event_signatures, id != :approval, do: {"event", signature})
  ]

  @doc false
  def __after_compile__(_env, _bytecode),
    do: Enum.each(@declarations, fn {kind, signature} -> declared!(@abi, kind, signature) end)

  @doc "Raises unless `abi` declares exactly this function or event signature."
  def declared!(abi, kind, signature) do
    [name] = Regex.run(~r/^(\w+)\(/, signature, capture: :all_but_first)

    Enum.any?(abi, fn
      %{"type" => ^kind, "name" => ^name, "inputs" => inputs} ->
        "#{name}(#{Enum.map_join(inputs, ",", & &1["type"])})" == signature

      _entry ->
        false
    end) || raise "pinned ABI is missing #{signature}"
  end

  def staking_address, do: @staking["address"]
  def stake_token_address, do: get_in(@staking, ["onchain_constants", "stake_token"])
  def usdc_address, do: get_in(@staking, ["onchain_constants", "usdc"])
  def encode_supply_denominator, do: @supply_denominator_selector
  def encode_available_regent_reward_inventory, do: @available_regent_selector
  def encode_reserved_usdc, do: @reserved_usdc_selector
  def encode_emission_apr_bps, do: @emission_apr_selector
  def supply_denominator_signature, do: @supply_denominator_signature

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
