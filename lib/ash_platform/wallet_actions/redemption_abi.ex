defmodule AshPlatform.WalletActions.RedemptionAbi do
  @moduledoc false

  alias AshPlatform.WalletActions.Abi

  @manifest_path Path.expand("../../../contracts/base-mainnet.json", __DIR__)
  @abi_path Path.expand("../../../contracts/abi/animata-redeemer.json", __DIR__)
  @external_resource @manifest_path
  @external_resource @abi_path

  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @abi @abi_path |> File.read!() |> Jason.decode!()
  @redeemer get_in(@manifest, ["contracts", "animata_redeemer"])
  @actions Map.new(@redeemer["prepared_actions"], &{&1["id"], &1})
  @reads Map.new(@redeemer["reads"], &{&1["id"], &1})

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
    address = Abi.normalize_address!(address)

    cond do
      address == Abi.normalize_address!(animata_i_address()) -> "animata_i"
      address == Abi.normalize_address!(animata_ii_address()) -> "animata_ii"
      true -> nil
    end
  rescue
    _ -> nil
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
