defmodule AshPlatform.Techtree.Payload do
  @moduledoc """
  Reads and checks a public Techtree manifest without persisting a report copy.
  """

  @default_gateway "https://ipfs.io/ipfs"
  @default_timeout 5_000
  @default_max_bytes 5_242_880
  @cid_pattern ~r/\A[0-9A-Za-z][0-9A-Za-z._-]{0,254}\z/
  @hash_pattern ~r/\A[0-9a-f]{64}\z/

  @type verification :: %{
          status: :not_available | :not_checked | :hash_matched | :unavailable,
          expected_hash: String.t() | nil,
          actual_hash: String.t() | nil
        }

  @spec reference(map()) :: %{
          cid: String.t() | nil,
          hash: String.t() | nil,
          uri: String.t() | nil,
          url: String.t() | nil
        }
  def reference(node) do
    cid = Map.get(node, :manifest_cid)
    hash = Map.get(node, :manifest_hash)

    %{
      cid: cid,
      hash: hash,
      uri: Map.get(node, :manifest_uri),
      url: if(is_binary(cid), do: payload_url(Map.get(node, :id), cid), else: nil)
    }
  end

  @spec fetch_if_referenced(map()) ::
          {:ok, %{bytes: nil, verification: verification(), uri: String.t() | nil}}
          | {:ok, %{bytes: binary(), verification: verification(), uri: String.t()}}
          | {:error, :artifact_unavailable}
  def fetch_if_referenced(node) do
    case {Map.get(node, :manifest_cid), Map.get(node, :manifest_hash),
          Map.get(node, :manifest_uri)} do
      {nil, nil, nil} ->
        {:ok,
         %{
           bytes: nil,
           verification: %{status: :not_available, expected_hash: nil, actual_hash: nil},
           uri: nil
         }}

      {_cid, _hash, _uri} ->
        fetch(node)
    end
  end

  @spec fetch(map()) ::
          {:ok, %{bytes: binary(), verification: verification(), uri: String.t()}}
          | {:error, :artifact_unavailable}
  def fetch(node) do
    with {:ok, cid} <- valid_cid(Map.get(node, :manifest_cid)),
         {:ok, expected_hash} <- valid_hash(Map.get(node, :manifest_hash)),
         {:ok, bytes} <- get_bytes(cid),
         true <- byte_size(bytes) <= max_bytes(),
         actual_hash <- sha256(bytes),
         true <- actual_hash == expected_hash,
         :ok <- valid_json_object(bytes) do
      {:ok,
       %{
         bytes: bytes,
         verification: %{
           status: :hash_matched,
           expected_hash: expected_hash,
           actual_hash: actual_hash
         },
         uri: Map.get(node, :manifest_uri) || "ipfs://#{cid}"
       }}
    else
      _result -> {:error, :artifact_unavailable}
    end
  end

  def payload_url(nil, _cid), do: nil

  def payload_url(node_id, cid) when is_binary(node_id) and is_binary(cid),
    do: "/api/techtree/v1/nodes/#{node_id}/payload"

  def payload_url(_node_id, _cid), do: nil

  def sha256(bytes) when is_binary(bytes),
    do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp get_bytes(cid) do
    options = [
      headers: [{"accept", "application/json"}, {"range", "bytes=0-#{max_bytes() - 1}"}],
      receive_timeout: timeout(),
      connect_options: [timeout: timeout()],
      decode_body: false,
      retry: false,
      redirect: false
    ]

    case http_client().get("#{gateway_url()}/#{cid}", options) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      _result -> {:error, :artifact_unavailable}
    end
  rescue
    _error -> {:error, :artifact_unavailable}
  end

  defp valid_cid(cid) when is_binary(cid) do
    if Regex.match?(@cid_pattern, cid), do: {:ok, cid}, else: {:error, :invalid}
  end

  defp valid_cid(_cid), do: {:error, :invalid}

  defp valid_hash(hash) when is_binary(hash) do
    if Regex.match?(@hash_pattern, hash), do: {:ok, hash}, else: {:error, :invalid}
  end

  defp valid_hash(_hash), do: {:error, :invalid}

  defp valid_json_object(bytes) do
    case Jason.decode(bytes) do
      {:ok, value} when is_map(value) -> :ok
      _result -> {:error, :invalid_json}
    end
  end

  defp http_client do
    :ash_platform
    |> Application.get_env(:techtree_payload, [])
    |> Keyword.get(:http_client, Req)
  end

  defp gateway_url do
    :ash_platform
    |> Application.get_env(:techtree_payload, [])
    |> Keyword.get(:gateway_url, @default_gateway)
    |> String.trim_trailing("/")
  end

  defp timeout do
    Application.get_env(:ash_platform, :techtree_payload, [])
    |> Keyword.get(:timeout, @default_timeout)
  end

  defp max_bytes do
    Application.get_env(:ash_platform, :techtree_payload, [])
    |> Keyword.get(:max_bytes, @default_max_bytes)
  end
end
