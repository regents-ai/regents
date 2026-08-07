defmodule AshPlatform.Techtree.PayloadTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Techtree.Payload

  defmodule HttpClient do
    def get(url, options) do
      send(self(), {:payload_request, url, options})

      case Process.get(:payload_http_result, {:error, :no_test_response}) do
        {:ok, %{status: status, body: body} = response} when is_binary(body) ->
          headers = Map.get(response, :headers, %{})
          request = Req.new()
          response = Req.Response.new(status: status, headers: headers)

          {response, halted?} = stream_chunks(options, request, response, [body])

          send(self(), {:payload_stream, response, halted?})
          {:ok, response}

        {:stream, %{status: status, chunks: chunks} = stream} ->
          request = Req.new()
          response = Req.Response.new(status: status, headers: Map.get(stream, :headers, %{}))

          {response, halted?} = stream_chunks(options, request, response, chunks)

          send(self(), {:payload_stream, response, halted?})
          {:ok, response}

        result ->
          result
      end
    end

    defp stream_chunks(options, request, response, chunks) do
      Enum.reduce_while(chunks, {response, false}, fn chunk, {response, _halted?} ->
        case stream_chunk(options, request, response, chunk) do
          {:cont, response} -> {:cont, {response, false}}
          {:halt, response} -> {:halt, {response, true}}
        end
      end)
    end

    defp stream_chunk(options, request, response, chunk) do
      case options[:into].({:data, chunk}, {request, response}) do
        {:cont, {_request, response}} -> {:cont, response}
        {:halt, {_request, response}} -> {:halt, response}
      end
    end
  end

  setup do
    previous = Application.get_env(:ash_platform, :techtree_payload)

    Application.put_env(:ash_platform, :techtree_payload,
      gateway_url: "https://gateway.test/ipfs",
      timeout: 25,
      max_bytes: 1_024,
      http_client: HttpClient
    )

    on_exit(fn -> restore(:techtree_payload, previous) end)
    :ok
  end

  test "fetches a referenced JSON object and reports matching bytes" do
    bytes = ~s({"schema_version":"uplift-report-v1","outcome":"positive"})
    hash = Payload.sha256(bytes)
    node = node("bafybeifetch", hash)
    Process.put(:payload_http_result, {:ok, %{status: 200, body: bytes}})

    assert {:ok, result} = Payload.fetch(node)
    assert result.bytes == bytes
    assert result.uri == "ipfs://bafybeifetch"
    assert result.verification == %{status: :hash_matched, expected_hash: hash, actual_hash: hash}
    assert_received {:payload_request, "https://gateway.test/ipfs/bafybeifetch", options}
    assert options[:decode_body] == false
    assert options[:receive_timeout] == 25
    assert is_function(options[:into], 2)
  end

  test "accepts a 206 response after streaming and verifying the assembled bytes" do
    bytes = ~s({"schema_version":1,"outcome":"positive"})
    hash = Payload.sha256(bytes)
    node = node("bafybei206", hash)

    Process.put(
      :payload_http_result,
      {:ok,
       %{
         status: 206,
         body: bytes,
         headers: %{
           "content-length" => [Integer.to_string(byte_size(bytes))],
           "content-range" => ["bytes 0-#{byte_size(bytes) - 1}/#{byte_size(bytes)}"]
         }
       }}
    )

    assert {:ok, result} = Payload.fetch(node)
    assert result.bytes == bytes
    assert result.verification.status == :hash_matched
  end

  test "halts an oversized stream before the response is materialized" do
    first = String.duplicate("a", 512)
    second = String.duplicate("b", 512)
    third = "c"
    node = node("bafybeioversized", String.duplicate("0", 64))
    Process.put(:payload_http_result, {:stream, %{status: 200, chunks: [first, second, third]}})

    assert {:error, :artifact_unavailable} = Payload.fetch(node)
    assert_received {:payload_stream, response, true}
    assert response.body == ""

    state = Req.Response.get_private(response, :ash_platform_techtree_payload)
    assert state.status == :too_large
    assert state.bytes == 1_024
    assert IO.iodata_to_binary(Enum.reverse(state.chunks)) == first <> second
  end

  test "does not fetch an unreferenced node" do
    assert {:ok, result} = Payload.fetch_if_referenced(%{manifest_cid: nil, manifest_hash: nil})
    assert result.bytes == nil
    assert result.verification.status == :not_available
    refute_received {:payload_request, _, _}
  end

  test "treats incomplete references as unavailable" do
    assert {:error, :artifact_unavailable} =
             Payload.fetch_if_referenced(%{manifest_cid: "bafybeiincomplete", manifest_hash: nil})
  end

  test "fails closed on a hash mismatch" do
    bytes = ~s({"schema_version":"uplift-report-v1"})
    node = node("bafybeimismatch", String.duplicate("0", 64))
    Process.put(:payload_http_result, {:ok, %{status: 200, body: bytes}})

    assert {:error, :artifact_unavailable} = Payload.fetch(node)
  end

  test "fails closed when the gateway reports a missing artifact" do
    bytes = ~s({"schema_version":"uplift-report-v1"})
    node = node("bafybeimissing", Payload.sha256(bytes))
    Process.put(:payload_http_result, {:ok, %{status: 404, body: ""}})

    assert {:error, :artifact_unavailable} = Payload.fetch(node)
  end

  test "fails closed on corrupt bytes even when their byte hash is displayed" do
    bytes = "not-json"
    node = node("bafybeicorrupt", Payload.sha256(bytes))
    Process.put(:payload_http_result, {:ok, %{status: 200, body: bytes}})

    assert {:error, :artifact_unavailable} = Payload.fetch(node)
  end

  defp node(cid, hash) do
    %{id: Ash.UUID.generate(), manifest_cid: cid, manifest_hash: hash, manifest_uri: nil}
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
