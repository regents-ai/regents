defmodule AshPlatform.RegentsClub.RpcClientTest do
  use ExUnit.Case, async: false

  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.RpcClient

  @safe_hash "0x" <> String.duplicate("5a", 32)

  defmodule HttpClient do
    def post(_url, options) do
      request = options[:json]
      send(Application.fetch_env!(:ash_platform, :test_regents_rpc_pid), request)

      result = Application.fetch_env!(:ash_platform, :test_regents_rpc_handler).(request)
      {:ok, %{status: 200, body: %{"result" => result}}}
    end
  end

  setup do
    keys = [
      :regents_club_http_client,
      :base_read_rpc_url,
      :test_regents_rpc_pid,
      :test_regents_rpc_handler
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

  test "minimal ABI decoders and the exact cutover event fail closed" do
    owner_word =
      "0x" <> String.duplicate("0", 24) <> String.trim_leading(RegentsClub.owner(), "0x")

    assert RegentsClub.decode_address(owner_word) == {:ok, RegentsClub.owner()}

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

  defp install(fun), do: Application.put_env(:ash_platform, :test_regents_rpc_handler, fun)

  defp abi_string(value) do
    padding = rem(32 - rem(byte_size(value), 32), 32)

    "0x" <>
      word(32) <>
      word(byte_size(value)) <> Base.encode16(value <> :binary.copy(<<0>>, padding), case: :lower)
  end

  defp word(value), do: value |> Integer.to_string(16) |> String.pad_leading(64, "0")
  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
