defmodule RegentPoints.Nfts do
  @moduledoc "Base ERC-721 holdings from the three collections on Regents' redemption page."
  @chain %{chain_id: 8453}
  # regents/platform/contracts/base-mainnet.json, animata_redeemer.onchain_constants.
  @collections [
    "0x78402119ec6349a0d41f12b54938de7bf783c923",
    "0x903c4c1e8b8532fbd3575482d942d493eb9266e2",
    "0x2208aadbdecd47d3b4430b5b75a175f6d885d487"
  ]
  def collections, do: @collections
  def rpc(method, args), do: RegentPoints.chain_client().rpc(@chain, method, args)
  defp number("0x" <> n), do: String.to_integer(n, 16)

  @doc "Holdings across the collections for `wallets` at the latest Base block."
  def latest(wallets) do
    case rpc("eth_getBlockByNumber", ["latest", false]) do
      {:ok, %{"number" => height, "hash" => hash}} ->
        holdings(wallets, %{number: number(height), hash: hash})

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :block_unavailable}
    end
  end

  @doc "Reads every collection at exactly the saved canonical block hash."
  def at_block(wallets, block), do: holdings(wallets, block)

  @doc "The last finalized Base block strictly before the full period-end timestamp."
  def period_end_block(stop) do
    with {:ok, head} <- block("finalized"),
         true <- DateTime.compare(head.at, stop) != :lt,
         {:ok, first} <- block(0),
         true <- DateTime.compare(first.at, stop) == :lt,
         {:ok, before} <- search(first, head, stop),
         {:ok, after_end} <- block(before.number + 1),
         true <-
           DateTime.compare(before.at, stop) == :lt and
             DateTime.compare(after_end.at, stop) != :lt and
             after_end.parent == before.hash do
      {:ok, before}
    else
      false -> {:error, :snapshot_block_not_finalized}
      {:error, _} = error -> error
    end
  end

  defp search(before, after_end, _stop) when after_end.number - before.number == 1,
    do: {:ok, before}

  defp search(before, after_end, stop) do
    middle = div(before.number + after_end.number, 2)

    with {:ok, found} <- block(middle) do
      if DateTime.compare(found.at, stop) == :lt,
        do: search(found, after_end, stop),
        else: search(before, found, stop)
    end
  end

  defp block(number) when is_integer(number) do
    with {:ok, block} <- block("0x" <> Integer.to_string(number, 16)),
         true <- block.number == number do
      {:ok, block}
    else
      false -> {:error, :invalid_snapshot_block}
      {:error, _} = error -> error
    end
  end

  defp block(tag) do
    case rpc("eth_getBlockByNumber", [tag, false]) do
      {:ok, %{"number" => height, "hash" => hash, "parentHash" => parent, "timestamp" => at}} ->
        with {:ok, height} <- hex_number(height),
             {:ok, timestamp} <- hex_number(at),
             {:ok, at} <- DateTime.from_unix(timestamp),
             true <- block_hash?(hash) and block_hash?(parent) do
          {:ok,
           %{number: height, hash: String.downcase(hash), parent: String.downcase(parent), at: at}}
        else
          _ -> {:error, :invalid_snapshot_block}
        end

      {:error, _} = error ->
        error

      _ ->
        {:error, :snapshot_block_unavailable}
    end
  end

  defp hex_number("0x" <> value) do
    case Integer.parse(value, 16) do
      {number, ""} when number >= 0 -> {:ok, number}
      _ -> {:error, :invalid_snapshot_block}
    end
  end

  defp hex_number(_), do: {:error, :invalid_snapshot_block}
  defp block_hash?(hash) when is_binary(hash), do: Regex.match?(~r/^0x[0-9a-fA-F]{64}$/, hash)
  defp block_hash?(_), do: false

  defp holdings(wallets, block) do
    calls = for wallet <- Enum.uniq(wallets), collection <- @collections, do: {wallet, collection}

    Enum.reduce_while(calls, {:ok, 0}, fn {wallet, collection}, {:ok, count} ->
      case balance(wallet, collection, block) do
        {:ok, balance} -> {:cont, {:ok, count + balance}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, count} -> {:ok, %{count: count, block: block.number, hash: block.hash}}
      error -> error
    end
  end

  defp balance("0x" <> wallet, collection, block) do
    data = "0x70a08231" <> String.pad_leading(wallet, 64, "0")

    case rpc("eth_call", [
           %{to: collection, data: data},
           %{blockHash: block.hash, requireCanonical: true}
         ]) do
      {:ok, "0x" <> raw} when byte_size(raw) == 64 -> parse_balance(raw)
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_nft_balance}
    end
  end

  defp parse_balance(raw) do
    case Integer.parse(raw, 16) do
      {balance, ""} -> {:ok, balance}
      _ -> {:error, :invalid_nft_balance}
    end
  end
end
