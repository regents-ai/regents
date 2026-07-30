defmodule AshPlatform.WalletActions.AuctionAbi do
  @moduledoc """
  Encodes the admitted auction actions.

  `submit_bid` uses the upstream four-argument convenience overload of the canonical
  five-argument `submitBid`. That overload defaults `prevTickPriceQ96` to
  `FLOOR_PRICE_Q96`; see Uniswap/continuous-clearing-auction
  `src/ContinuousClearingAuction.sol` lines 635-641.
  """

  alias AshPlatform.WalletActions.Abi

  @abi_path Path.expand("../../../contracts/abi/continuous-clearing-auction.json", __DIR__)
  @external_resource @abi_path

  @abi @abi_path |> File.read!() |> Jason.decode!()
  @uint128_max Integer.pow(2, 128) - 1
  @uint256_max Integer.pow(2, 256) - 1
  @entries %{
    "submit_bid" => {"submitBid(uint256,uint128,address,bytes)", "0x140fe8ee"},
    "exit_bid" => {"exitBid(uint256)", "0x8e4deb17"},
    "return_quote_token" => {"exitBid(uint256)", "0x8e4deb17"},
    "claim_bid" => {"claimTokens(uint256)", "0x46e04a2f"}
  }

  for {_id, {signature, _selector}} <- @entries do
    unless Enum.any?(@abi, fn
             %{"type" => "function", "name" => name, "inputs" => inputs} ->
               "#{name}(#{Enum.map_join(inputs, ",", & &1["type"])})" == signature

             _ ->
               false
           end) do
      raise "pinned auction ABI is missing #{signature}"
    end
  end

  def encode_submit_bid(max_price_q96, amount_raw, owner_address)
      when is_integer(amount_raw) and amount_raw in 0..@uint128_max do
    {_signature, selector} = Map.fetch!(@entries, "submit_bid")

    selector <>
      encode_uint256!(max_price_q96) <>
      encode_uint256!(amount_raw) <>
      encode_address!(owner_address) <>
      encode_uint256!(128) <>
      encode_uint256!(0)
  end

  def encode_submit_bid(_max_price_q96, _amount_raw, _owner_address),
    do: raise(ArgumentError, "bid amount exceeds uint128")

  def encode_position(action, onchain_bid_id)
      when action in ["exit_bid", "return_quote_token", "claim_bid"] do
    {_signature, selector} = Map.fetch!(@entries, action)
    selector <> encode_uint256!(onchain_bid_id)
  end

  def encode_approval(spender, amount_raw),
    do: Abi.encode_erc20("approve", [spender, amount_raw])

  defp encode_address!(address) do
    address
    |> Abi.normalize_address!()
    |> String.trim_leading("0x")
    |> String.pad_leading(64, "0")
  end

  defp encode_uint256!(value) when is_integer(value) and value in 0..@uint256_max do
    value
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(64, "0")
  end

  defp encode_uint256!(_value), do: raise(ArgumentError, "uint256 value is invalid")
end
