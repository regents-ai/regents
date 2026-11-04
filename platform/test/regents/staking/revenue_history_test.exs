defmodule Regents.Staking.RevenueHistoryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Regents.Staking.RevenueHistory

  @week 604_800
  @denim_block 40_000_000
  @start 1_700_000_000

  # Base's clock: a block every two seconds, then after Denim five a second, each
  # stamped in whole seconds, so up to five share one.
  defp stamp(number) when number <= @denim_block, do: @start + 2 * number
  defp stamp(number), do: @start + 2 * @denim_block + div(number - @denim_block, 5)

  defp timestamp_at(number), do: {:ok, stamp(number)}

  defp head(number), do: %{number: number, hash: "0xhead", timestamp: stamp(number)}

  defp first_block(number) do
    {:ok, _history, window} =
      RevenueHistory.read(nil, head(number), fn _, _ -> {:ok, []} end, &timestamp_at/1)

    window.usdc_received_from_block
  end

  property "the window opens at the first block stamped within the last seven days" do
    check all(
            offset <- integer((-2 * @week)..(10 * @week)),
            max_runs: 200
          ) do
      number = @denim_block + offset
      first = first_block(number)
      since = stamp(number) - @week

      assert stamp(first) > since
      assert stamp(first - 1) <= since
    end
  end

  test "seven days hold ten times the blocks once they all come five a second" do
    before_denim = @denim_block
    assert before_denim - first_block(before_denim) + 1 == 302_400

    after_denim = @denim_block + 8 * 24 * 3600 * 5
    assert (after_denim - first_block(after_denim) + 1) in 3_023_996..3_024_000
  end

  # An endpoint keeps only so much history: Base Sepolia's answers "pruned history
  # unavailable" for older blocks, so nothing beyond the window's limit is asked for.
  test "no block older than the most seven days can hold is asked for" do
    number = @denim_block + 1_000_000
    lowest = number - 5 * @week + 1

    at = fn block ->
      if block < lowest, do: {:error, :chain_unavailable}, else: timestamp_at(block)
    end

    assert {:ok, _history, %{usdc_received_from_block: first}} =
             RevenueHistory.read(nil, head(number), fn _, _ -> {:ok, []} end, at)

    assert first == first_block(number)
  end

  test "a chain younger than seven days is all in the window" do
    assert first_block(1_000) == 0
  end

  test "a pass re-reads the newest 300 blocks and drops what left the window" do
    number = @denim_block + 1_000_000
    first = first_block(number)
    kept_head = number - 1_500
    from = kept_head - 299

    event = fn block, raw ->
      %{
        "block_number" => block,
        "block_hash" => "0xold",
        "transaction_hash" => "0xold",
        "log_index" => 0,
        "received_raw" => raw
      }
    end

    previous = %{
      "block_number" => kept_head,
      "block_hash" => "0xold",
      "events" => [event.(first - 1, "1"), event.(first, "20"), event.(from, "300")]
    }

    fetch = fn asked_from, asked_to ->
      send(self(), {:asked, asked_from, asked_to})
      {:ok, []}
    end

    assert {:ok, history, window} =
             RevenueHistory.read(previous, head(number), fetch, &timestamp_at/1)

    assert_received {:asked, ^from, ^number}
    assert Enum.map(history["events"], & &1["received_raw"]) == ["20"]
    assert window.usdc_received_7d_raw == "20"
    assert RevenueHistory.start(previous, first) == from
  end

  test "a head behind the history is refused before any block is read" do
    previous = %{"block_number" => 100, "block_hash" => "0xold", "events" => []}

    assert RevenueHistory.read(
             previous,
             head(99),
             fn _, _ -> flunk("asked for logs") end,
             fn _ -> flunk("asked for a block") end
           ) == {:error, :head_regressed}
  end
end
