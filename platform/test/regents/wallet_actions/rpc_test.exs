defmodule Regents.WalletActions.RpcTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Regents.BaseRpcStub, as: Stub
  alias Regents.WalletActions.Rpc

  @hash "0x" <> String.duplicate("ab", 32)
  @target "0x2222222222222222222222222222222222222222"
  @data "0xabcdef"

  defmodule Client do
    def post(_url, options) do
      send(self(), {:wallet_http_client, options[:json]})
      {:ok, %{status: 200, body: %{"result" => "0x2105"}}}
    end
  end

  defmodule FailingClient do
    def post(_url, _options), do: {:error, :offline}
  end

  setup do
    previous = Application.get_env(:regents, :wallet_http_client)
    Application.put_env(:regents, :wallet_http_client, Client)
    on_exit(fn -> restore(:wallet_http_client, previous) end)
  end

  test "ONE_EXACT_HASH_LANGUAGE: lowercase 0x and exactly 64 hexadecimal characters, nothing else" do
    hex = String.duplicate("ab", 32)
    truncated = "0x" <> String.duplicate("a", 63)

    for canonical <- [@hash, "0x" <> String.upcase(hex), "0x" <> String.duplicate("aB", 32)],
        do: assert(Rpc.valid_hash?(canonical), "#{inspect(canonical)} is canonical")

    for malformed <- [
          truncated <> "\n",
          "0x" <> hex <> "\n",
          truncated <> " ",
          truncated <> "\t",
          truncated,
          "0x" <> hex <> "a",
          "0x" <> String.duplicate("g", 64),
          "0X" <> hex,
          "",
          nil,
          :hash,
          String.to_charlist(@hash)
        ],
        do: refute(Rpc.valid_hash?(malformed), "#{inspect(malformed)} is not canonical")
  end

  test "uses the generic wallet client by default" do
    assert :ok = Rpc.verify_base_chain()
    assert_received {:wallet_http_client, %{method: "eth_chainId"}}
  end

  test "uses the generic wallet log scope by default" do
    Application.put_env(:regents, :wallet_http_client, FailingClient)

    log =
      capture_log(fn -> assert {:error, :chain_unavailable} = Rpc.request("eth_chainId", []) end)

    assert log =~ "wallet chain read failed"
    refute log =~ "staking chain read failed"
  end

  test "STRICT_ABI_DECODING: malformed scalar evidence is unavailable" do
    Stub.install(:wallet_http_client, fn _data, _state -> Process.get(:abi_result) end)
    block = %{hash: Stub.safe_hash()}

    Process.put(:abi_result, Stub.uint(7))
    assert {:ok, 7} = Rpc.call_uint(@target, @data, block)

    Process.put(:abi_result, Stub.uint(0))
    assert {:ok, false} = Rpc.call_bool(@target, @data, block)
    Process.put(:abi_result, Stub.uint(1))
    assert {:ok, true} = Rpc.call_bool(@target, @data, block)

    Process.put(:abi_result, Stub.uint(2))
    assert {:error, :invalid_chain_response} = Rpc.call_bool(@target, @data, block)

    address = "0x" <> String.duplicate("ab", 20)
    Process.put(:abi_result, "0x" <> Stub.address_word(address))
    assert {:ok, ^address} = Rpc.call_address(@target, @data, block)

    for malformed <- [
          "0x" <> String.duplicate("a", 63),
          "0x" <> String.duplicate("a", 65),
          "0x" <> String.duplicate("g", 64)
        ] do
      Process.put(:abi_result, malformed)
      assert {:error, :invalid_chain_response} = Rpc.call_uint(@target, @data, block)
      assert {:error, :invalid_chain_response} = Rpc.call_address(@target, @data, block)
    end

    Process.put(:abi_result, "0x" <> String.duplicate("1", 24) <> String.duplicate("a", 40))
    assert {:error, :invalid_chain_response} = Rpc.call_address(@target, @data, block)

    Process.put(:abi_result, "0x" <> Stub.hex_word(1) <> Stub.hex_word(2))
    assert {:ok, [1, 2]} = Rpc.call_words(@target, @data, block, 2)

    Process.put(:abi_result, "0x" <> Stub.hex_word(1) <> Stub.hex_word(2) <> Stub.hex_word(3))
    assert {:error, :invalid_chain_response} = Rpc.call_words(@target, @data, block, 2)
  end

  # The Stake and Redeem readings are pinned to this head, so it is one proved
  # Base block or nothing.
  test "ONE_LATEST_BLOCK: the latest head is one proved Base block, or nothing" do
    Stub.install(:wallet_http_client, fn _data, _state -> Stub.uint(0) end)

    assert Rpc.latest_block() == {:ok, %{number: 0x20, hash: Stub.latest_hash()}}
    assert_received {:rpc, "eth_getBlockByNumber", ["latest", false]}

    Stub.put(%{chain_id: "0x1"})
    assert Rpc.latest_block() == {:error, :wrong_chain}

    Stub.put(%{
      chain_id: "0x2105",
      latest_block: %{"number" => "later", "hash" => Stub.latest_hash()}
    })

    assert Rpc.latest_block() == {:error, :invalid_block_header}
  end

  defp restore(key, nil), do: Application.delete_env(:regents, key)
  defp restore(key, value), do: Application.put_env(:regents, key, value)
end
