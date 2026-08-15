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

  def staking_address, do: @staking["address"]
  def stake_token_address, do: get_in(@staking, ["onchain_constants", "stake_token"])
  def usdc_address, do: get_in(@staking, ["onchain_constants", "usdc"])

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
