defmodule AshPlatform.WalletActions.BuybackAbi do
  @moduledoc """
  Encodes the prepared-only legacy buyback settlement interface.

  The archived Platform application at `b760a45b` pins the five-argument
  `settleTreasuryBuyback` selector. The vendored current router implementation removed
  that action; its pre-removal implementation used a different four-argument interface.
  The chain admission records both facts and does not treat this ABI as deployment proof.
  """

  alias AshPlatform.WalletActions.Abi

  @abi_path Path.expand(
              "../../../contracts/abi/regent-staking-revenue-router-buyback.json",
              __DIR__
            )
  @external_resource @abi_path

  @signature "settleTreasuryBuyback(bytes32,address,uint256,uint256,bytes32)"
  @selector "0xd8df40b6"
  @uint256_max Integer.pow(2, 256) - 1
  @abi @abi_path |> File.read!() |> Jason.decode!()

  unless Enum.any?(@abi, fn
           %{"type" => "function", "name" => name, "inputs" => inputs} ->
             "#{name}(#{Enum.map_join(inputs, ",", & &1["type"])})" == @signature

           _ ->
             false
         end) do
    raise "pinned buyback ABI is missing #{@signature}"
  end

  def encode_settlement(subject_id, treasury, usdc_amount, minimum_regent_output, source_ref) do
    @selector <>
      encode_bytes32!(subject_id) <>
      encode_address!(treasury) <>
      encode_uint256!(usdc_amount) <>
      encode_uint256!(minimum_regent_output) <>
      encode_bytes32!(source_ref)
  end

  defp encode_address!(address) do
    address
    |> Abi.normalize_address!()
    |> String.trim_leading("0x")
    |> String.pad_leading(64, "0")
  end

  defp encode_bytes32!("0x" <> value)
       when byte_size(value) == 64 do
    if String.match?(value, ~r/^[0-9a-fA-F]+$/),
      do: String.downcase(value),
      else: raise(ArgumentError, "bytes32 value is invalid")
  end

  defp encode_bytes32!(_value), do: raise(ArgumentError, "bytes32 value is invalid")

  defp encode_uint256!(value) when is_integer(value) and value in 0..@uint256_max do
    value
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(64, "0")
  end

  defp encode_uint256!(_value), do: raise(ArgumentError, "uint256 value is invalid")
end
