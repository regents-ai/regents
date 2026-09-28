defmodule Regents.ChainClientTest do
  use ExUnit.Case, async: false

  alias Regents.BaseRpcStub, as: Stub
  alias Regents.ChainClient

  @wallet "0x1111111111111111111111111111111111111111"
  @base %{chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"}

  setup do
    Stub.install(:wallet_http_client, fn _method, _params -> :unavailable end)
    :ok
  end

  test "SENT_STEP: a sent hash reads as nothing until Base has it, then as Base answers" do
    hash = "0x" <> String.duplicate("ab", 32)
    assert {:ok, nil} = ChainClient.transaction(@base, hash)
    assert {:ok, nil} = ChainClient.receipt(@base, hash)

    Stub.put(%{
      transactions: %{hash => %{"hash" => hash, "from" => @wallet}},
      receipts: %{hash => Stub.receipt(hash, "0x10", [], "0x0")}
    })

    assert {:ok, %{"hash" => ^hash, "from" => @wallet}} = ChainClient.transaction(@base, hash)
    assert {:ok, %{"status" => "0x0"}} = ChainClient.receipt(@base, hash)
    assert_received {:rpc, "eth_getTransactionByHash", [^hash]}
    assert_received {:rpc, "eth_getTransactionReceipt", [^hash]}
  end
end
