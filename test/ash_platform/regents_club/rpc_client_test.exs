defmodule AshPlatform.RegentsClub.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.RpcClient
  alias AshPlatform.WalletActions.Envelope
  alias AshPlatform.WalletActions.Rpc

  @safe_hash "0x" <> String.duplicate("5a", 32)
  @transaction_hash "0x" <> String.duplicate("ab", 32)
  @receipt_block_number 47
  @risk_copy "Collection-wide metadata cutover for Regents Club tokens 1 through 1998. No prepared rollback exists."

  defmodule HttpClient do
    def post(_url, options) do
      request = options[:json]
      send(Application.fetch_env!(:ash_platform, :test_regents_rpc_pid), request)

      case Application.fetch_env!(:ash_platform, :test_regents_rpc_handler).(request) do
        {:rpc_error, error} -> {:ok, %{status: 200, body: %{"error" => error}}}
        result -> {:ok, %{status: 200, body: %{"result" => result}}}
      end
    end
  end

  setup do
    keys = [
      :regents_club_http_client,
      :base_read_rpc_url,
      :test_regents_rpc_pid,
      :test_regents_rpc_handler,
      :regents_club_test_runtime_hasher
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:ash_platform, &1)})
    Application.put_env(:ash_platform, :regents_club_http_client, HttpClient)
    Application.put_env(:ash_platform, :base_read_rpc_url, "https://base.example.test")
    Application.put_env(:ash_platform, :test_regents_rpc_pid, self())

    on_exit(fn -> Enum.each(previous, fn {key, value} -> restore(key, value) end) end)
    :ok
  end

  test "readiness accepts only Base chain identity" do
    install(fn
      %{method: "eth_chainId"} -> "0x2105"
    end)

    assert RpcClient.readiness() == :ok

    install(fn
      %{method: "eth_chainId"} -> "0x1"
    end)

    assert RpcClient.readiness() == {:error, :wrong_chain}
  end

  test "status pins runtime and contract reads to one canonical safe block hash" do
    install(fn
      %{method: "eth_chainId"} ->
        "0x2105"

      %{method: "eth_getBlockByNumber", params: ["safe", false]} ->
        %{"number" => "0x20", "hash" => @safe_hash}

      %{method: "eth_getCode"} ->
        "0x"
    end)

    assert RpcClient.status() == {:error, :runtime_mismatch}
    assert_receive %{method: "eth_getCode", params: [address, block]}
    assert address == RegentsClub.contract_address()
    assert block == %{blockHash: @safe_hash, requireCanonical: true}
  end

  test "final confirmation obtains a finalized head and preserves expected RPC reverts" do
    install(fn
      %{method: "eth_chainId"} ->
        "0x2105"

      %{method: "eth_getBlockByNumber", params: ["finalized", false]} ->
        %{"number" => "0x1f", "hash" => @safe_hash}

      %{method: "eth_call"} ->
        {:rpc_error, %{"code" => -32_000, "message" => "reverted"}}
    end)

    assert Rpc.finalized_block(client_key: :regents_club_http_client) ==
             {:ok, %{number: 31, hash: @safe_hash}}

    assert Rpc.request_preserving_rpc_error(
             "eth_call",
             [%{}],
             client_key: :regents_club_http_client
           ) == {:rpc_error, %{"code" => -32_000, "message" => "reverted"}}

    assert_receive %{method: "eth_getBlockByNumber", params: ["finalized", false]}
  end

  test "RPC failure logs expose only method and failure class" do
    marker = "sensitive-regents-provider-detail"
    install(fn _request -> raise marker end)

    log = capture_log(fn -> assert RpcClient.readiness() == {:error, :chain_unavailable} end)

    assert log =~ "regents_club_metadata chain read failed"
    assert log =~ "eth_chainId"
    refute log =~ marker
    refute log =~ "https://base.example.test"
  end

  test "preparation rechecks every invariant and both simulations at canonical block hashes" do
    runtime = "0x" <> String.duplicate("00", RegentsClub.runtime_bytes())

    Application.put_env(:ash_platform, :regents_club_test_runtime_hasher, fn
      ^runtime -> {:ok, RegentsClub.runtime_keccak256()}
      _other -> :error
    end)

    install(&preflight_result(&1, runtime, expected_revert()))

    assert {:ok, prepared} = RpcClient.prepare(RegentsClub.owner())
    assert prepared.anchor == %{number: 32, hash: @safe_hash}
    assert prepared.owner == RegentsClub.owner()
    assert prepared.base_uri == RegentsClub.old_base_uri()
    assert prepared.total_supply == 1_998
    assert prepared.erc4906_supported
    assert prepared.owner_simulation == "success"
    assert prepared.non_owner_simulation == "revert"
    assert prepared.gas_estimate == 81_189

    assert prepared.token_uris == %{
             first: RegentsClub.old_base_uri() <> "1",
             last: RegentsClub.old_base_uri() <> "1998"
           }

    requests = drain_requests()
    assert Enum.count(requests, &(&1.method == "eth_getBlockByNumber")) == 2
    assert Enum.count(requests, &(&1.method == "eth_getCode")) == 2

    for %{method: method, params: params} <- requests,
        method in ["eth_getCode", "eth_call", "eth_estimateGas"] do
      assert List.last(params) == %{blockHash: @safe_hash, requireCanonical: true}
    end

    assert Enum.count(requests, fn
             %{method: "eth_call", params: [%{from: from}, _block]} ->
               from == "0x0000000000000000000000000000000000000001"

             _request ->
               false
           end) == 2
  end

  test "non-owner simulation accepts only an actual revert response" do
    runtime = "0x" <> String.duplicate("00", RegentsClub.runtime_bytes())

    Application.put_env(:ash_platform, :regents_club_test_runtime_hasher, fn
      ^runtime -> {:ok, RegentsClub.runtime_keccak256()}
      _other -> :error
    end)

    install(&preflight_result(&1, runtime, %{"code" => -32_602, "message" => "invalid params"}))

    assert RpcClient.prepare(RegentsClub.owner()) ==
             {:error, :invalid_non_owner_simulation}

    install(&preflight_result(&1, runtime, :accepted))
    assert RpcClient.prepare(RegentsClub.owner()) == {:error, :non_owner_simulation_succeeded}
  end

  test "minimal ABI decoders and the exact cutover event fail closed" do
    owner_word =
      "0x" <> String.duplicate("0", 24) <> String.trim_leading(RegentsClub.owner(), "0x")

    assert RegentsClub.decode_address(owner_word) == {:ok, RegentsClub.owner()}
    assert RegentsClub.decode_uint("0x" <> word(1998)) == {:ok, 1998}
    assert RegentsClub.decode_bool("0x" <> word(1)) == {:ok, true}
    assert RegentsClub.decode_bool("0x" <> word(2)) == :error

    encoded_uri = abi_string(RegentsClub.new_base_uri())
    assert RegentsClub.decode_string(encoded_uri) == {:ok, RegentsClub.new_base_uri()}
    assert RegentsClub.decode_string(encoded_uri <> "00") == :error

    exact_log = %{
      "address" => RegentsClub.contract_address(),
      "topics" => [RegentsClub.batch_metadata_topic()],
      "data" => "0x" <> word(1) <> word(1998)
    }

    assert RegentsClub.batch_metadata_event?([exact_log])

    refute RegentsClub.batch_metadata_event?([
             put_in(exact_log["data"], "0x" <> word(0) <> word(1998))
           ])
  end

  test "observation waits for finalized canonical evidence before accepting the exact post-state" do
    runtime = "0x" <> String.duplicate("00", RegentsClub.runtime_bytes())
    envelope = observation_envelope()

    Application.put_env(:ash_platform, :regents_club_test_runtime_hasher, fn
      ^runtime -> {:ok, RegentsClub.runtime_keccak256()}
      _other -> :error
    end)

    install(&observation_result(&1, runtime, @receipt_block_number - 1))
    assert RpcClient.observe(envelope, @transaction_hash) == {:ok, :pending}

    pending_requests = drain_requests()
    refute Enum.any?(pending_requests, &(&1.method == "eth_getCode"))

    install(&observation_result(&1, runtime, @receipt_block_number))

    assert {:ok, {:finalized, result}} = RpcClient.observe(envelope, @transaction_hash)
    assert result.transaction_hash == @transaction_hash
    assert result.block_number == @receipt_block_number
    assert result.block_hash == String.downcase(block_hash(@receipt_block_number))
    assert result.finality_block_number == @receipt_block_number
    assert result.base_uri == RegentsClub.new_base_uri()

    requests = drain_requests()
    refute Enum.any?(requests, &(&1.params == ["safe", false]))

    for %{method: method, params: params} <- requests, method in ["eth_getCode", "eth_call"] do
      assert List.last(params) == %{
               blockHash: String.downcase(block_hash(@receipt_block_number)),
               requireCanonical: true
             }
    end
  end

  test "missing-hash recovery scans only the fixed 64-block post-anchor window" do
    envelope = observation_envelope()

    install(fn
      %{method: "eth_chainId"} ->
        "0x2105"

      %{method: "eth_getBlockByNumber", params: ["finalized", false]} ->
        %{"number" => "0xc8", "hash" => block_hash(200)}

      %{method: "eth_getBlockByNumber", params: [encoded, true]} ->
        {:ok, number} = quantity(encoded)
        %{"number" => encoded, "hash" => block_hash(number), "transactions" => []}
    end)

    assert RpcClient.recover(envelope) == {:ok, :pending}

    scanned =
      drain_requests()
      |> Enum.filter(&match?(%{method: "eth_getBlockByNumber", params: [_, true]}, &1))

    assert length(scanned) == 64
    assert hd(scanned).params == [hex_quantity(43), true]
    assert List.last(scanned).params == [hex_quantity(106), true]
  end

  defp install(fun), do: Application.put_env(:ash_platform, :test_regents_rpc_handler, fun)

  defp preflight_result(%{method: "eth_chainId"}, _runtime, _non_owner), do: "0x2105"

  defp preflight_result(
         %{method: "eth_getBlockByNumber", params: ["safe", false]},
         _runtime,
         _non_owner
       ),
       do: %{"number" => "0x20", "hash" => @safe_hash}

  defp preflight_result(%{method: "eth_getCode"}, runtime, _non_owner), do: runtime

  defp preflight_result(
         %{method: "eth_estimateGas", params: [%{from: from}, _block]},
         _runtime,
         _non_owner
       ) do
    if from == RegentsClub.owner(), do: "0x13d25", else: raise("unexpected estimate signer")
  end

  defp preflight_result(
         %{method: "eth_call", params: [%{data: data} = transaction, _block]},
         _runtime,
         non_owner
       ) do
    cond do
      data == RegentsClub.calldata() and Map.get(transaction, :from) == RegentsClub.owner() ->
        "0x"

      data == RegentsClub.calldata() and
          Map.get(transaction, :from) == "0x0000000000000000000000000000000000000001" ->
        if non_owner == :accepted, do: "0x", else: {:rpc_error, non_owner}

      true ->
        Map.fetch!(preflight_reads(), data)
    end
  end

  defp preflight_reads do
    %{
      RegentsClub.owner_calldata() => address(RegentsClub.owner()),
      RegentsClub.base_uri_calldata() => abi_string(RegentsClub.old_base_uri()),
      RegentsClub.total_supply_calldata() => "0x" <> word(1_998),
      RegentsClub.supports_erc4906_calldata() => "0x" <> word(1),
      RegentsClub.token_uri_calldata(1) => abi_string(RegentsClub.old_base_uri() <> "1"),
      RegentsClub.token_uri_calldata(1_998) => abi_string(RegentsClub.old_base_uri() <> "1998")
    }
  end

  defp expected_revert, do: %{"code" => -32_000, "message" => "execution reverted"}

  defp observation_result(%{method: "eth_chainId"}, _runtime, _finalized_number), do: "0x2105"

  defp observation_result(
         %{method: "eth_getBlockByNumber", params: ["finalized", false]},
         _runtime,
         finalized_number
       ),
       do: %{
         "number" => hex_quantity(finalized_number),
         "hash" => block_hash(finalized_number)
       }

  defp observation_result(
         %{method: "eth_getBlockByNumber", params: [encoded, false]},
         _runtime,
         _finalized_number
       ) do
    {:ok, number} = quantity(encoded)
    %{"number" => encoded, "hash" => block_hash(number)}
  end

  defp observation_result(
         %{method: "eth_getTransactionByHash", params: [@transaction_hash]},
         _runtime,
         _finalized_number
       ) do
    %{
      "hash" => @transaction_hash,
      "from" => RegentsClub.owner(),
      "to" => RegentsClub.contract_address(),
      "input" => RegentsClub.calldata(),
      "value" => "0x0"
    }
  end

  defp observation_result(
         %{method: "eth_getTransactionReceipt", params: [@transaction_hash]},
         _runtime,
         _finalized_number
       ) do
    %{
      "transactionHash" => @transaction_hash,
      "blockNumber" => hex_quantity(@receipt_block_number),
      "blockHash" => block_hash(@receipt_block_number),
      "status" => "0x1",
      "logs" => [batch_log()]
    }
  end

  defp observation_result(%{method: "eth_getCode"}, runtime, _finalized_number), do: runtime

  defp observation_result(
         %{method: "eth_call", params: [%{data: data}, _block]},
         _runtime,
         _finalized_number
       ) do
    cond do
      data == RegentsClub.owner_calldata() ->
        address(RegentsClub.owner())

      data == RegentsClub.base_uri_calldata() ->
        abi_string(RegentsClub.new_base_uri())

      data == RegentsClub.total_supply_calldata() ->
        "0x" <> word(1_998)

      data == RegentsClub.supports_erc4906_calldata() ->
        "0x" <> word(1)

      data == RegentsClub.token_uri_calldata(1) ->
        abi_string(RegentsClub.new_base_uri() <> "1")

      data == RegentsClub.token_uri_calldata(1_998) ->
        abi_string(RegentsClub.new_base_uri() <> "1998")

      true ->
        raise "unexpected observation call"
    end
  end

  defp observation_envelope do
    Envelope.new(RegentsClub.action(), RegentsClub.owner(), RegentsClub.calldata(),
      to: RegentsClub.contract_address(),
      resource: "regents_club_metadata",
      contract_name: "RegentsClub",
      risk_copy: @risk_copy,
      arguments: %{
        attempt_id: "c56a4180-65aa-42ec-a945-5fd21dec0538",
        new_base_uri: RegentsClub.new_base_uri()
      },
      metadata: %{
        anchor_block_number: 42,
        anchor_block_hash: @safe_hash,
        current_base_uri: RegentsClub.old_base_uri(),
        boundary_token_uris: %{
          first: RegentsClub.old_base_uri() <> "1",
          last: RegentsClub.old_base_uri() <> "1998"
        },
        total_supply: 1_998,
        erc4906_supported: true,
        owner_simulation: "success",
        non_owner_simulation: "revert",
        gas_estimate: "81189",
        runtime_keccak256: RegentsClub.runtime_keccak256(),
        calldata_keccak256: RegentsClub.calldata_keccak256()
      }
    )
  end

  defp batch_log do
    %{
      "address" => RegentsClub.contract_address(),
      "topics" => [RegentsClub.batch_metadata_topic()],
      "data" => "0x" <> word(1) <> word(1_998)
    }
  end

  defp drain_requests(requests \\ []) do
    receive do
      %{jsonrpc: "2.0"} = request -> drain_requests([request | requests])
    after
      0 -> Enum.reverse(requests)
    end
  end

  defp address(value),
    do:
      "0x" <>
        (value |> String.trim_leading("0x") |> String.downcase() |> String.pad_leading(64, "0"))

  defp abi_string(value) do
    padding = rem(32 - rem(byte_size(value), 32), 32)

    "0x" <>
      word(32) <>
      word(byte_size(value)) <> Base.encode16(value <> :binary.copy(<<0>>, padding), case: :lower)
  end

  defp word(value), do: value |> Integer.to_string(16) |> String.pad_leading(64, "0")
  defp hex_quantity(value), do: "0x" <> Integer.to_string(value, 16)

  defp quantity("0x" <> value) do
    case Integer.parse(value, 16) do
      {number, ""} -> {:ok, number}
      _error -> :error
    end
  end

  defp block_hash(value), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")
  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
