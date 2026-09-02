defmodule AshPlatform.WalletActions.TransactionObserverTest do
  use ExUnit.Case, async: false

  alias AshPlatform.BaseRpcStub
  alias AshPlatform.WalletActions.TransactionObserver

  @hash "0x" <> String.duplicate("ab", 32)
  @signer "0x1111111111111111111111111111111111111111"
  @target "0x2222222222222222222222222222222222222222"
  @data "0x1234"

  defmodule UnreadableUntil do
    @moduledoc "Fails this many reads from `:unreadable_reads`, then answers normally."

    def post(url, options) do
      case Process.get(:unreadable_reads, 0) do
        0 ->
          BaseRpcStub.post(url, options)

        remaining ->
          Process.put(:unreadable_reads, remaining - 1)
          {:error, %Req.TransportError{reason: :timeout}}
      end
    end
  end

  setup do
    BaseRpcStub.install(:staking_http_client, fn _data, _state -> :unavailable end)
    :ok
  end

  # The safe head here trails the latest one, as Base's does by well over a
  # minute: the same receipt answers at the latest head and would not at the
  # safe head, which is the whole reason a person stopped seeing a confirmation.
  test "confirms a transaction mined into the latest block on the first poll" do
    BaseRpcStub.put(%{
      latest_block: %{"number" => "0x10", "hash" => BaseRpcStub.latest_hash()},
      safe_block: %{"number" => "0x0f", "hash" => BaseRpcStub.safe_hash()},
      receipts: %{@hash => BaseRpcStub.receipt(@hash, "0x10", [])},
      transactions: %{@hash => transaction()}
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0]) == :success
    assert_received {:rpc, "eth_getBlockByNumber", ["latest", false]}
    refute_received {:rpc, "eth_getBlockByNumber", ["safe", false]}
  end

  test "keeps a displaced block and an unobserved transaction unsettled" do
    BaseRpcStub.put(%{
      receipts: %{@hash => BaseRpcStub.receipt(@hash, "0x10", [])},
      transactions: %{@hash => transaction()},
      blocks: %{
        "0x10" => %{"number" => "0x10", "hash" => "0x" <> String.duplicate("ef", 32)}
      }
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0]) == :delayed

    BaseRpcStub.put(%{receipts: %{}, transactions: %{}, blocks: %{}})

    assert TransactionObserver.observe_rpc(payload(), :staking, [0]) == :delayed
  end

  # Base confirms a block about every two seconds, so the schedule a person
  # actually waits on is one minute of one poll per block, starting immediately.
  test "watches for one minute, one poll per Base block, beginning without delay" do
    assert length(TransactionObserver.delays()) == 31
    assert Enum.sum(TransactionObserver.delays()) == 60_000
    assert hd(TransactionObserver.delays()) == 0
  end

  test "re-reads the head on every scheduled poll before an exhausted schedule is delayed" do
    BaseRpcStub.put(%{receipts: %{}, transactions: %{}})

    assert TransactionObserver.observe_rpc(payload(), :staking, [0, 0, 0]) == :delayed
    assert reads("eth_getBlockByNumber", ["latest", false]) == 3
  end

  # At the chain head a node may not have caught up to the block a receipt
  # names, so a failed read is a read to repeat, not an answer. It never becomes
  # an answer either: only a canonical receipt confirms or reverts.
  test "a failed read re-polls inside the schedule and still confirms" do
    Application.put_env(:ash_platform, :staking_http_client, UnreadableUntil)
    Process.put(:unreadable_reads, 2)

    BaseRpcStub.put(%{
      receipts: %{@hash => BaseRpcStub.receipt(@hash, "0x10", [])},
      transactions: %{@hash => transaction()}
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0, 0, 0]) == :success
    assert Process.get(:unreadable_reads) == 0
  end

  test "a chain that stays unreadable is reported only once the schedule is exhausted" do
    Application.put_env(:ash_platform, :staking_http_client, UnreadableUntil)
    Process.put(:unreadable_reads, 99)

    assert TransactionObserver.observe_rpc(payload(), :staking, [0, 0, 0]) == :unavailable
    assert Process.get(:unreadable_reads) == 96
  end

  # Only a read that did not happen is repeated. A decided answer about this
  # provider, receipt or transaction would come back identical on every later
  # poll, so waiting out the minute would tell the person nothing new.
  test "a decided verdict answers on the first poll and does not spend the schedule" do
    BaseRpcStub.put(%{
      receipts: %{@hash => BaseRpcStub.receipt(@hash, "0x10", [])},
      transactions: %{@hash => Map.put(transaction(), "input", "0xdeadbeef")}
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0, 0, 0]) == :unavailable
    assert reads("eth_getBlockByNumber", ["latest", false]) == 1

    BaseRpcStub.put(%{chain_id: "0x1"})

    assert TransactionObserver.observe_rpc(payload(), :staking, [0, 0, 0]) == :unavailable
    assert reads("eth_chainId", []) == 1

    Application.put_env(:ash_platform, :staking_http_client, UnreadableUntil)
    Process.put(:unreadable_reads, 99)

    assert TransactionObserver.observe_rpc(payload(), :staking, [0, 0, 0]) == :unavailable
    assert Process.get(:unreadable_reads) == 96
  end

  test "an unreadable chain never answers success or revert, whatever the receipt says" do
    Application.put_env(:ash_platform, :staking_http_client, UnreadableUntil)

    for receipt <- [
          BaseRpcStub.receipt(@hash, "0x10", []),
          BaseRpcStub.receipt(@hash, "0x10", [], "0x0")
        ] do
      Process.put(:unreadable_reads, 99)

      BaseRpcStub.put(%{
        receipts: %{@hash => receipt},
        transactions: %{@hash => transaction()}
      })

      assert TransactionObserver.observe_rpc(payload(), :staking, [0, 0, 0]) == :unavailable
    end
  end

  test "reports a canonical revert and refuses changed transaction identity" do
    BaseRpcStub.put(%{
      receipts: %{@hash => BaseRpcStub.receipt(@hash, "0x10", [], "0x0")},
      transactions: %{@hash => transaction()}
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0]) == :reverted

    BaseRpcStub.put(%{
      transactions: %{@hash => Map.put(transaction(), "input", "0xdeadbeef")}
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0]) == :unavailable
  end

  defp payload,
    do: %{"hash" => @hash, "signer" => @signer, "to" => @target, "data" => @data}

  # How many times this test's mailbox saw exactly this request.
  defp reads(method, params) do
    receive do
      {:rpc, ^method, ^params} -> 1 + reads(method, params)
      {:rpc, _method, _params} -> reads(method, params)
    after
      0 -> 0
    end
  end

  defp transaction,
    do: %{
      "hash" => @hash,
      "from" => @signer,
      "to" => @target,
      "input" => @data,
      "value" => "0x0"
    }
end
