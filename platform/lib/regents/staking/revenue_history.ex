defmodule Regents.Staking.RevenueHistory do
  @moduledoc """
  A rolling public projection of the contract's deposits, not an accounting ledger.

  Retains the blocks of the last seven days, by the timestamps the chain gives
  them, and replaces the newest minute of recorded blocks on each pass (Base makes
  five blocks a second). Replacing that overlap removes orphaned deposits and
  accepts late-indexed logs. Deeper reorganizations require rebuilding this
  projection.
  """

  alias Regents.WalletActions.{Abi, Rpc}

  @window_seconds 604_800
  # Base's fastest: five blocks in every second of the window. Older blocks are
  # never asked for, since an endpoint may no longer keep them.
  @most_blocks 5 * @window_seconds
  @overlap 300

  def read(previous, block, fetch, timestamp_at) do
    with :ok <- forward_head(previous, block),
         since = block.timestamp - @window_seconds,
         lowest = max(block.number - @most_blocks + 1, 0),
         {:ok, first} <- first_after(lowest, block.number, since, timestamp_at),
         from = start(previous, first),
         {:ok, logs} <- fetch.(from, block.number),
         {:ok, events} <- events(logs, from, block) do
      all = retained(previous, first, from) ++ events
      total = Enum.reduce(all, 0, &(&2 + String.to_integer(&1["received_raw"])))

      {:ok,
       %{
         "block_number" => block.number,
         "block_hash" => block.hash,
         "events" => all
       },
       %{
         usdc_received_from_block: first,
         usdc_received_7d_raw: Integer.to_string(total),
         usdc_received_7d: Rpc.format_units(total, 6)
       }}
    end
  end

  defp forward_head(%{"block_number" => head}, %{number: number}) when number < head,
    do: {:error, :head_regressed}

  defp forward_head(_previous, _block), do: :ok

  # The first block stamped after `since`. Block times never go back and up to five
  # blocks share a second, so this finds the lowest of them by halving the range.
  defp first_after(low, low, _since, _timestamp_at), do: {:ok, low}

  defp first_after(low, high, since, timestamp_at) do
    middle = div(low + high, 2)

    with {:ok, timestamp} <- timestamp_at.(middle) do
      if timestamp > since,
        do: first_after(low, middle, since, timestamp_at),
        else: first_after(middle + 1, high, since, timestamp_at)
    end
  end

  @doc "The block a pass reads from, given the history it extends and the window's first block."
  def start(nil, first), do: first
  def start(%{"block_number" => head}, first), do: max(first, head - @overlap + 1)

  defp retained(nil, _first, _from), do: []

  defp retained(%{"events" => events}, first, from),
    do: Enum.filter(events, &(&1["block_number"] >= first && &1["block_number"] < from))

  defp events(logs, from, block) when is_list(logs) do
    Enum.reduce_while(logs, {:ok, %{}}, fn log, {:ok, found} ->
      with {:ok, event} <- event(log, from, block),
           key = {event["transaction_hash"], event["log_index"]},
           existing = Map.get(found, key),
           true <- is_nil(existing) || existing == event do
        {:cont, {:ok, Map.put(found, key, event)}}
      else
        _invalid -> {:halt, {:error, :invalid_chain_response}}
      end
    end)
    |> case do
      {:ok, found} ->
        events = found |> Map.values() |> Enum.sort_by(&{&1["block_number"], &1["log_index"]})

        consistent? =
          events
          |> Enum.group_by(& &1["block_number"])
          |> Enum.all?(fn {_number, block_events} ->
            match?([_], Enum.uniq_by(block_events, & &1["block_hash"])) &&
              Enum.uniq_by(block_events, & &1["log_index"]) == block_events
          end)

        if consistent?, do: {:ok, events}, else: {:error, :invalid_chain_response}

      error ->
        error
    end
  end

  defp events(_logs, _from, _block), do: {:error, :invalid_chain_response}

  defp event(log, from, block) when is_map(log) do
    with false <- Map.get(log, "removed", false),
         {:ok, number} <- quantity(log["blockNumber"]),
         true <- number >= from && number <= block.number,
         {:ok, index} <- quantity(log["logIndex"]),
         {:ok, hash} <- hash(log["blockHash"]),
         {:ok, transaction} <- hash(log["transactionHash"]),
         true <- number != block.number || hash == block.hash,
         {:ok, received} <- Abi.usdc_revenue_received([log]) do
      {:ok,
       %{
         "block_number" => number,
         "block_hash" => hash,
         "transaction_hash" => transaction,
         "log_index" => index,
         "received_raw" => Integer.to_string(received)
       }}
    else
      _invalid -> {:error, :invalid_chain_response}
    end
  end

  defp event(_log, _from, _block), do: {:error, :invalid_chain_response}

  defp quantity("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {value, ""} when value >= 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp quantity(_value), do: :error

  defp hash(value) when is_binary(value) do
    if String.match?(value, ~r/\A0x[0-9a-fA-F]{64}\z/),
      do: {:ok, String.downcase(value)},
      else: :error
  end

  defp hash(_value), do: :error
end
