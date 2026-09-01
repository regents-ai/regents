defmodule AshPlatform.WalletActions.TransactionObserverTest do
  use ExUnit.Case, async: false

  alias AshPlatform.BaseRpcStub
  alias AshPlatform.WalletActions.TransactionObserver

  @hash "0x" <> String.duplicate("ab", 32)
  @signer "0x1111111111111111111111111111111111111111"
  @target "0x2222222222222222222222222222222222222222"
  @data "0x1234"

  setup do
    BaseRpcStub.install(:staking_http_client, fn _data, _state -> :unavailable end)
    :ok
  end

  test "reports success only from the exact transaction in a canonical safe block" do
    BaseRpcStub.put(%{
      receipts: %{@hash => BaseRpcStub.receipt(@hash, "0x10", [])},
      transactions: %{@hash => transaction()}
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0]) == :success
  end

  test "keeps receipts above the safe head and displaced blocks unsettled" do
    BaseRpcStub.put(%{
      safe_block: %{"number" => "0x0f", "hash" => BaseRpcStub.safe_hash()},
      receipts: %{@hash => BaseRpcStub.receipt(@hash, "0x10", [])},
      transactions: %{@hash => transaction()}
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0]) == :delayed

    BaseRpcStub.put(%{
      safe_block: %{"number" => "0x20", "hash" => BaseRpcStub.safe_hash()},
      blocks: %{
        "0x10" => %{"number" => "0x10", "hash" => "0x" <> String.duplicate("ef", 32)}
      }
    })

    assert TransactionObserver.observe_rpc(payload(), :staking, [0]) == :delayed
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

  defp transaction,
    do: %{
      "hash" => @hash,
      "from" => @signer,
      "to" => @target,
      "input" => @data,
      "value" => "0x0"
    }
end
