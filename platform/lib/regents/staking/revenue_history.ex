defmodule Regents.Staking.RevenueHistory do
  @moduledoc """
  A rolling public projection of the contract's deposits, not an accounting ledger.

  Retains seven days of Base blocks and replaces the newest 30 recorded blocks
  on each pass. Replacing that overlap removes orphaned deposits and accepts
  late-indexed logs. Deeper reorganizations require rebuilding this projection.
  """

  alias Regents.WalletActions.{Abi, Rpc}

  @window 302_400
  @overlap 30

  def read(previous, block, fetch) do
    first = max(block.number - @window + 1, 0)

    with :ok <- forward_head(previous, block),
         from = start(previous, first),
         {:ok, logs} <- fetch.(from, block.number),
         {:ok, events} <- events(logs, from, block),
         retained = retained(previous, first, from),
         all = retained ++ events do
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

  defp start(nil, first), do: first
  defp start(%{"block_number" => head}, first), do: max(first, head - @overlap + 1)

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
            length(Enum.uniq_by(block_events, & &1["block_hash"])) == 1 &&
              length(Enum.uniq_by(block_events, & &1["log_index"])) == length(block_events)
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
