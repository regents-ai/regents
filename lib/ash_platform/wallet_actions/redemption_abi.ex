defmodule AshPlatform.WalletActions.RedemptionAbi do
  @moduledoc false

  alias AshPlatform.WalletActions.{Abi, Address}

  @manifest_path Path.expand("../../../contracts/base-mainnet.json", __DIR__)
  @abi_path Path.expand("../../../contracts/abi/animata-redeemer.json", __DIR__)
  @external_resource @manifest_path
  @external_resource @abi_path

  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @abi @abi_path |> File.read!() |> Jason.decode!()
  @redeemer get_in(@manifest, ["contracts", "animata_redeemer"])
  @actions Map.new(@redeemer["prepared_actions"], &{&1["id"], &1})
  @reads Map.new(@redeemer["reads"], &{&1["id"], &1})

  @event_signatures %{
    approval_for_all: "ApprovalForAll(address,address,bool)",
    redeemed: "Redeemed(address,address,uint256,uint256)",
    claimed: "Claimed(address,uint256)"
  }
  # `ApprovalForAll` belongs to the Animata collections, so only the redeemer's
  # own events are proved against the redeemer ABI, the moment it is compiled.
  @after_compile __MODULE__
  @declared_events for(
                     {id, signature} <- @event_signatures,
                     id != :approval_for_all,
                     do: signature
                   )

  @doc false
  def __after_compile__(_env, _bytecode),
    do: Enum.each(@declared_events, &Abi.declared!(@abi, "event", &1))

  def event_signature(id), do: Map.fetch!(@event_signatures, id)
  def event_topic(id), do: id |> event_signature() |> Abi.topic0()

  def redeemer_address, do: @redeemer["address"]
  def animata_i_address, do: get_in(@redeemer, ["onchain_constants", "animata_i"])
  def animata_ii_address, do: get_in(@redeemer, ["onchain_constants", "animata_ii"])

  def result_collection_address,
    do: get_in(@redeemer, ["onchain_constants", "result_collection"])

  def usdc_address, do: get_in(@redeemer, ["onchain_constants", "usdc"])
  def regent_address, do: get_in(@redeemer, ["onchain_constants", "regent"])
  def price_atomic, do: get_in(@redeemer, ["onchain_constants", "usdc_price_atomic"])
  def payout_atomic, do: get_in(@redeemer, ["onchain_constants", "regent_payout_atomic"])
  def max_token_id, do: get_in(@redeemer, ["onchain_constants", "max_source_token_id"])

  def vest_duration_seconds,
    do: get_in(@redeemer, ["onchain_constants", "vest_duration_seconds"])

  def collection("animata_i"), do: {:ok, Abi.normalize_address!(animata_i_address())}
  def collection("animata_ii"), do: {:ok, Abi.normalize_address!(animata_ii_address())}
  def collection(_collection), do: {:error, :invalid_collection}

  def collection_id(address) do
    cond do
      Address.equal?(address, animata_i_address()) -> "animata_i"
      Address.equal?(address, animata_ii_address()) -> "animata_ii"
      true -> nil
    end
  end

  @doc """
  The exact contract one prepared redemption action targets, and the name a
  review shows for it.

  The action layer and the chain client ask this one question of the pinned
  manifest, so a review, a dispatch claim and a receipt can never disagree about
  which contract this action belongs to.
  """
  @spec action_identity(map()) :: {:ok, String.t(), String.t()} | {:error, atom()}
  def action_identity(%{action: "approve_nft_collection", arguments: arguments}) do
    collection = Map.get(arguments, :collection, Map.get(arguments, "collection"))

    case collection_name(collection) do
      nil -> {:error, :invalid_collection}
      name -> {:ok, Abi.normalize_address!(collection), name}
    end
  end

  def action_identity(%{action: "approve_exact_usdc"}),
    do: {:ok, Abi.normalize_address!(usdc_address()), "USDC"}

  def action_identity(%{action: action}) when action in ["redeem", "claim"],
    do: {:ok, Abi.normalize_address!(redeemer_address()), "AnimataRedeemer"}

  def action_identity(_envelope), do: {:error, :invalid_action}

  @doc "The name an eligible Animata collection is reviewed under, or `nil`."
  def collection_name(address) do
    case collection_id(address) do
      "animata_i" -> "Animata I"
      "animata_ii" -> "Animata II"
      nil -> nil
    end
  end

  def encode_action(id, arguments) when is_binary(id) and is_list(arguments) do
    @actions |> Map.fetch!(id) |> encode(arguments)
  end

  def encode_read(id, arguments \\ []) when is_binary(id) and is_list(arguments) do
    @reads |> Map.fetch!(id) |> encode(arguments)
  end

  def encode_erc20(id, arguments) when id in ["approve", "balance_of", "allowance"] do
    encode_standard("erc20", id, arguments)
  end

  def encode_erc721(id, arguments)
      when id in ["owner_of", "is_approved_for_all", "set_approval_for_all"] do
    encode_standard("erc721", id, arguments)
  end

  @doc "The exact collection-wide operator approval this transaction had to record."
  def collection_approved?(logs, collection, owner, operator) do
    with {:ok, {[owner_word, operator_word], [1]}} <-
           Abi.one_event(logs, event_topic(:approval_for_all), collection, 2, 1),
         {:ok, ^owner} <- Abi.word_address(owner_word),
         {:ok, ^operator} <- Abi.word_address(operator_word) do
      true
    else
      _contradiction -> false
    end
  end

  @doc """
  The redemption this transaction recorded, as its positive result token ID.

  The event carries no USDC amount, so `newId` is a Regents Club token and never
  a value.
  """
  def redeemed(logs, signer, collection, token_id) do
    with {:ok, {[user_word, source_word, ^token_id], [result_token_id]}} <-
           Abi.one_event(logs, event_topic(:redeemed), redeemer_address(), 3, 1),
         {:ok, ^signer} <- Abi.word_address(user_word),
         {:ok, ^collection} <- Abi.word_address(source_word),
         true <- result_token_id > 0 do
      {:ok, result_token_id}
    else
      _contradiction -> :error
    end
  end

  @doc "The positive account-wide claim this transaction recorded, which carries no NFT identity."
  def claimed(logs, signer) do
    with {:ok, {[user_word], [amount]}} <-
           Abi.one_event(logs, event_topic(:claimed), redeemer_address(), 1, 1),
         {:ok, ^signer} <- Abi.word_address(user_word),
         true <- amount > 0 do
      {:ok, amount}
    else
      _contradiction -> :error
    end
  end

  defp encode(entry, arguments) do
    function = function_for_signature!(entry["signature"])
    encode_inputs(entry, function["inputs"] || [], arguments)
  end

  defp encode_standard(interface, id, arguments) do
    entry =
      @manifest["standard_interfaces"]
      |> Map.fetch!(interface)
      |> Enum.find(&(&1["id"] == id)) || raise "missing #{interface} ABI entry #{id}"

    [encoded_types] = Regex.run(~r/^\w+\((.*)\)$/, entry["signature"], capture: :all_but_first)

    inputs =
      if encoded_types == "",
        do: [],
        else: Enum.map(String.split(encoded_types, ","), &%{"type" => &1})

    encode_inputs(entry, inputs, arguments)
  end

  defp encode_inputs(entry, inputs, arguments) do
    if length(inputs) != length(arguments),
      do: raise(ArgumentError, "ABI argument count does not match #{entry["signature"]}")

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
    end) || raise "pinned redemption ABI is missing #{signature}"
  end

  defp encode_static("address", address) do
    address
    |> Abi.normalize_address!()
    |> String.trim_leading("0x")
    |> String.pad_leading(64, "0")
  end

  defp encode_static("uint256", value) when is_integer(value) and value >= 0,
    do: value |> Integer.to_string(16) |> String.pad_leading(64, "0")

  defp encode_static("bool", value) when is_boolean(value),
    do: if(value, do: String.pad_leading("1", 64, "0"), else: String.duplicate("0", 64))

  defp encode_static(type, _value), do: raise(ArgumentError, "unsupported ABI input #{type}")
end
