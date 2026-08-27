defmodule AshPlatform.Autolaunch.TreasuryChainClientTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Autolaunch.TreasuryChainClient
  alias AshPlatform.TestAutolaunchTreasuryChainClient, as: Client

  @safe_hash "0x" <> String.duplicate("aa", 32)
  @address "0x9999999999999999999999999999999999999999"

  defmodule HttpClient do
    def post(_url, options) do
      request = options[:json]
      send(self(), {:treasury_rpc, request.method, request.params})

      case response(request.method, request.params) do
        {:error, reason} ->
          {:ok, %{status: 200, body: %{"error" => %{"message" => to_string(reason)}}}}

        result ->
          {:ok, %{status: 200, body: %{"result" => result}}}
      end
    end

    defp response("eth_chainId", _params), do: "0x2105"

    defp response("eth_getBlockByNumber", ["safe", false]),
      do: %{"number" => "0x20", "hash" => state().safe_hash}

    defp response("eth_getBlockByNumber", ["0x20", false]),
      do: %{"number" => "0x20", "hash" => state().safe_hash}

    defp response("eth_getCode", [_address, block]), do: code(block)
    defp response(_method, _params), do: {:error, :unexpected_request}

    defp code(block) do
      if block == %{blockHash: state().safe_hash, requireCanonical: true},
        do: state().runtime_code,
        else: {:error, :mixed_block_read}
    end

    defp state, do: Process.get(:treasury_rpc_state)
  end

  setup do
    previous_client = Application.get_env(:ash_platform, :autolaunch_treasury_chain_client)
    previous_http = Application.get_env(:ash_platform, :autolaunch_treasury_http_client)
    previous_url = Application.get_env(:ash_platform, :base_read_rpc_url)

    on_exit(fn ->
      restore(:autolaunch_treasury_chain_client, previous_client)
      restore(:autolaunch_treasury_http_client, previous_http)
      restore(:base_read_rpc_url, previous_url)
      Application.delete_env(:ash_platform, :test_autolaunch_treasury_observation)
    end)

    :ok
  end

  test "THE_CONFIGURED_CLIENT_OWNS_BOTH_OBSERVATION_AND_CANONICAL_RECHECK" do
    Client.install()
    address = "0x9999999999999999999999999999999999999999"

    assert {:ok, observation} = TreasuryChainClient.observe(address, %{})
    assert observation.admitted_safe?
    assert TreasuryChainClient.canonical?(observation.block.number, observation.block.hash)

    Client.install(canonical?: false)
    refute TreasuryChainClient.canonical?(observation.block.number, observation.block.hash)
  end

  test "PRODUCTION_READS_ONE_CANONICAL_EIP_1898_BLOCK_AND_NEVER_GUESSES_CODE" do
    Application.delete_env(:ash_platform, :autolaunch_treasury_chain_client)
    Application.put_env(:ash_platform, :autolaunch_treasury_http_client, HttpClient)
    Application.put_env(:ash_platform, :base_read_rpc_url, "https://provider.invalid")

    for runtime <- [
          "0x",
          "0xef0100" <> String.duplicate("11", 20),
          "0xef0100" <> String.duplicate("11", 19),
          "0x6001600055"
        ] do
      Process.put(:treasury_rpc_state, %{safe_hash: @safe_hash, runtime_code: runtime})
      assert {:ok, observation} = TreasuryChainClient.observe(@address, %{})
      assert observation.runtime_code == runtime
      refute observation.admitted_safe?

      assert_received {:treasury_rpc, "eth_getCode",
                       [@address, %{blockHash: @safe_hash, requireCanonical: true}]}
    end

    assert TreasuryChainClient.canonical?(0x20, @safe_hash)

    Process.put(:treasury_rpc_state, %{
      safe_hash: "0x" <> String.duplicate("bb", 32),
      runtime_code: "0x"
    })

    refute TreasuryChainClient.canonical?(0x20, @safe_hash)
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
