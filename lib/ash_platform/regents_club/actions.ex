defmodule AshPlatform.RegentsClub.Actions do
  @moduledoc false

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.RegentsClub
  alias AshPlatform.WalletActions.{Address, Envelope}

  @resource "regents_club_metadata"
  @contract_name "RegentsClub"
  @risk_copy "Collection-wide metadata cutover for Regents Club tokens 1 through 1998. No prepared rollback exists."
  @observation_seconds 45 * 60
  @media_origin "https://media.regents.sh"
  @representative_tokens [1, 1000, 1998]
  @media_concurrency 16

  def deployment_readiness(%{lineage: lineage, account_id: account_id}) do
    callback = fn account ->
      with true <- RegentsClub.authorized_account?(account),
           :ok <- functional_readiness(account) do
        {:ok, :ok}
      else
        false -> {:error, :not_authorized}
        {:error, reason} -> {:error, reason}
      end
    end

    case SessionAuthority.transact_lease(lineage, account_id, callback) do
      {:ok, :ok} -> :ok
      {:error, :stale_authority} -> {:error, :session_unavailable}
      result -> result
    end
  end

  def deployment_readiness(_lease), do: {:error, :session_unavailable}
  def status, do: chain_client().status()
  def observe_hash(envelope, hash), do: chain_client().observe(envelope, hash)
  def recover_unknown(envelope), do: chain_client().recover(envelope)

  def prepare(active_wallet, attempt_id, %{lineage: lineage, account_id: account_id}) do
    with true <- RegentsClub.enabled?(),
         true <- RegentsClub.valid_attempt_id?(attempt_id),
         {:ok, signer} <- Address.normalize(active_wallet),
         true <- signer == RegentsClub.owner() do
      callback = fn account -> prepare_current(account, signer, attempt_id) end

      case SessionAuthority.transact_lease(lineage, account_id, callback) do
        {:error, :stale_authority} -> {:error, :session_unavailable}
        result -> result
      end
    else
      false -> {:error, :not_authorized}
      :error -> {:error, :not_authorized}
    end
  end

  def prepare(_active_wallet, _attempt_id, _lease), do: {:error, :session_unavailable}

  def valid_envelope?(envelope) do
    Envelope.valid?(envelope, validation()) and exact_envelope?(envelope)
  rescue
    _ -> false
  end

  def valid_observation_envelope?(envelope) do
    Envelope.valid_for_confirmation?(envelope, validation()) and exact_envelope?(envelope)
  rescue
    _ -> false
  end

  def observation_open?(envelope) when is_map(envelope) do
    with {:ok, deadline, _offset} <-
           DateTime.from_iso8601(field(field(envelope, :metadata), :observation_deadline)),
         :lt <- DateTime.compare(Envelope.current_time(), deadline) do
      true
    else
      _ -> false
    end
  end

  def observation_open?(_envelope), do: false

  defp prepare_current(account, signer, attempt_id) do
    with true <- RegentsClub.authorized_account?(account),
         true <- signer == RegentsClub.owner(),
         :ok <- functional_readiness(account),
         {:ok, preflight} <- chain_client().prepare(signer),
         envelope <- envelope(attempt_id, signer, preflight),
         true <- valid_envelope?(envelope) do
      {:ok, envelope}
    else
      false -> {:error, :not_authorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp envelope(attempt_id, signer, preflight) do
    prepared_at = Envelope.current_time()

    Envelope.new(RegentsClub.action(), signer, RegentsClub.calldata(),
      to: RegentsClub.contract_address(),
      resource: @resource,
      contract_name: @contract_name,
      risk_copy: @risk_copy,
      prepared_at: prepared_at,
      arguments: %{attempt_id: attempt_id, new_base_uri: RegentsClub.new_base_uri()},
      metadata: %{
        anchor_block_number: preflight.anchor.number,
        anchor_block_hash: preflight.anchor.hash,
        current_base_uri: preflight.base_uri,
        boundary_token_uris: preflight.token_uris,
        total_supply: preflight.total_supply,
        erc4906_supported: preflight.erc4906_supported,
        owner_simulation: preflight.owner_simulation,
        non_owner_simulation: preflight.non_owner_simulation,
        gas_estimate: Integer.to_string(preflight.gas_estimate),
        runtime_keccak256: preflight.runtime_keccak256,
        calldata_keccak256: RegentsClub.calldata_keccak256(),
        observation_deadline:
          prepared_at |> DateTime.add(@observation_seconds, :second) |> DateTime.to_iso8601()
      }
    )
  end

  defp exact_envelope?(envelope) do
    exact_transaction?(envelope) and
      exact_arguments?(field(envelope, :arguments)) and
      exact_preflight?(field(envelope, :metadata)) and
      exact_observation_deadline?(envelope)
  end

  defp exact_transaction?(envelope) do
    checks = [
      field(envelope, :resource) == @resource,
      field(envelope, :action) == RegentsClub.action(),
      field(envelope, :chain_id) == RegentsClub.chain_id(),
      field(envelope, :to) == RegentsClub.contract_address(),
      field(envelope, :value) == "0",
      field(envelope, :data) == RegentsClub.calldata(),
      field(envelope, :expected_signer) == RegentsClub.owner(),
      field(envelope, :risk_copy) == @risk_copy
    ]

    Enum.all?(checks)
  end

  defp exact_arguments?(arguments) when is_map(arguments) do
    field(arguments, :new_base_uri) == RegentsClub.new_base_uri() and
      RegentsClub.valid_attempt_id?(field(arguments, :attempt_id))
  end

  defp exact_arguments?(_arguments), do: false

  defp exact_preflight?(metadata) when is_map(metadata) do
    anchor_number = field(metadata, :anchor_block_number)
    gas_estimate = field(metadata, :gas_estimate)

    checks = [
      is_integer(anchor_number) and anchor_number >= 0,
      valid_hash?(field(metadata, :anchor_block_hash)),
      field(metadata, :current_base_uri) == RegentsClub.old_base_uri(),
      field(metadata, :runtime_keccak256) == RegentsClub.runtime_keccak256(),
      field(metadata, :total_supply) == 1998,
      field(metadata, :erc4906_supported) == true,
      field(metadata, :owner_simulation) == "success",
      field(metadata, :non_owner_simulation) == "revert",
      field(metadata, :calldata_keccak256) == RegentsClub.calldata_keccak256(),
      positive_integer_string?(gas_estimate),
      boundary_uris?(field(metadata, :boundary_token_uris), RegentsClub.old_base_uri())
    ]

    Enum.all?(checks)
  end

  defp exact_preflight?(_metadata), do: false

  defp exact_observation_deadline?(envelope) do
    with {:ok, prepared_at, _offset} <- DateTime.from_iso8601(field(envelope, :prepared_at)),
         {:ok, deadline, _offset} <-
           DateTime.from_iso8601(field(field(envelope, :metadata), :observation_deadline)) do
      DateTime.diff(deadline, prepared_at, :second) == @observation_seconds
    else
      _ -> false
    end
  end

  defp validation do
    [
      to: RegentsClub.contract_address(),
      signer: RegentsClub.owner(),
      resource: @resource,
      contract_name: @contract_name,
      action: RegentsClub.action()
    ]
  end

  defp functional_readiness(account) do
    with true <- RegentsClub.authorized_account?(account),
         :ok <- public_privy_bootstrap(),
         :ok <- server_verifier(),
         true <- Application.get_env(:ash_platform, :regents_club_privy_origin_canary, false),
         :ok <- media_attestation(),
         :ok <- media_probes(),
         :ok <- chain_client().readiness() do
      :ok
    else
      false -> {:error, :privy_origin_canary_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp public_privy_bootstrap do
    case Application.get_env(:ash_platform, :privy, [])[:app_id] do
      value when is_binary(value) ->
        if(String.trim(value) == "", do: {:error, :privy_unavailable}, else: :ok)

      _ ->
        {:error, :privy_unavailable}
    end
  end

  defp server_verifier do
    verifier = Application.get_env(:ash_platform, :privy_verifier, AshPlatform.Privy)
    config = Application.get_env(:ash_platform, :privy, [])

    capable? =
      Code.ensure_loaded?(verifier) and function_exported?(verifier, :verify_session_pair, 1)

    configured? = verifier != AshPlatform.Privy or present?(config[:verification_key])
    if capable? and configured?, do: :ok, else: {:error, :privy_verifier_unavailable}
  end

  defp media_attestation do
    attestation = RegentsClub.media_release_attestation()

    checks = [
      Application.get_env(:ash_platform, :regents_club_media_full_corpus_attestation) ==
        attestation["release_manifest_sha256"],
      attestation["full_corpus_route_count"] ==
        RegentsClub.last_token_id() - RegentsClub.first_token_id() + 1,
      attestation["live_probe_token_ids"] == @representative_tokens,
      attestation["operator_attestation_required"] == true,
      present?(attestation["active_image_digest"]),
      present?(attestation["artifact_manifest_sha256"]),
      present?(attestation["production_deployment_verification_sha256"])
    ]

    if Enum.all?(checks), do: :ok, else: {:error, :media_full_corpus_attestation_required}
  end

  if Mix.env() == :test do
    defp media_probes do
      case Application.get_env(:ash_platform, :regents_club_media_probe_module) do
        module when is_atom(module) and not is_nil(module) ->
          if Code.ensure_loaded?(module) and function_exported?(module, :media_readiness, 0),
            do: module.media_readiness(),
            else: {:error, :media_probe_failed}

        _ ->
          live_media_probes()
      end
    end
  else
    defp media_probes, do: live_media_probes()
  end

  defp live_media_probes do
    client = Application.get_env(:ash_platform, :regents_club_media_http_client, Req)

    with {:ok, %{status: 200, body: body}} <- get(client, @media_origin <> "/healthz"),
         true <- is_binary(body) and String.trim(body) == "ok",
         :ok <- verify_live_release(client) do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp verify_live_release(client) do
    RegentsClub.first_token_id()..RegentsClub.last_token_id()
    |> Task.async_stream(&verify_live_token(client, &1),
      max_concurrency: @media_concurrency,
      ordered: false,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, :ok}, :ok ->
        {:cont, :ok}

      _failure, :ok ->
        {:halt, {:error, :media_probe_failed}}
    end)
  end

  defp verify_live_token(client, token_id) do
    with {:ok, metadata} <- metadata(client, token_id),
         image when is_binary(image) <- metadata["image"],
         animation when is_binary(animation) <- metadata["animation_url"],
         true <- exact_asset_url?(image, token_id, ".png"),
         true <- exact_asset_url?(animation, token_id, ".mp4"),
         :ok <- verify_asset(client, image, :png, token_id),
         :ok <- verify_asset(client, animation, :mp4, token_id) do
      :ok
    else
      _ ->
        {:error, :media_probe_failed}
    end
  end

  defp metadata(client, token_id) do
    with {:ok, %{status: 200, headers: headers, body: body}} <-
           get(client, @media_origin <> "/metadata/#{token_id}"),
         true <- content_type?(headers, "application/json"),
         true <- is_binary(body) and byte_size(body) > 0,
         {:ok, metadata} when is_map(metadata) <- Jason.decode(body) do
      {:ok, metadata}
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp verify_asset(client, url, kind, token_id) when token_id in @representative_tokens,
    do: verify_representative_asset(client, url, kind)

  defp verify_asset(client, url, kind, _token_id) when kind in [:png, :mp4] do
    with {:ok, %{status: 206, headers: headers, body: body}} <-
           get(client, url, [{"range", "bytes=0-0"}]),
         true <- content_type?(headers, asset_content_type(kind)),
         true <- valid_partial_range?(headers, body) do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp verify_representative_asset(client, url, kind) do
    with {:ok, %{status: 200, headers: headers, body: body}} <- get(client, url),
         true <- content_type?(headers, asset_content_type(kind)),
         true <- decodable_asset?(kind, body),
         {:ok, %{status: 206, headers: range_headers, body: range_body}} <-
           get(client, url, [{"range", "bytes=0-0"}]),
         true <- valid_range?(range_headers, range_body, body) do
      :ok
    else
      _ ->
        {:error, :media_probe_failed}
    end
  end

  defp exact_asset_url?(url, token_id, extension) do
    expected_path =
      case extension do
        ".png" -> "/images/animata/cards/#{token_id}.png"
        ".mp4" -> "/videos/regents-club/#{token_id}-v1.mp4"
      end

    case URI.new(url) do
      {:ok,
       %URI{scheme: "https", host: "media.regents.sh", path: path, query: nil, fragment: nil}}
      when is_binary(path) ->
        path == expected_path

      _ ->
        false
    end
  end

  defp valid_range?(headers, <<first_byte>>, <<first_byte, _rest::binary>> = full_body),
    do: header(headers, "content-range") == "bytes 0-0/#{byte_size(full_body)}"

  defp valid_range?(_headers, _range_body, _full_body), do: false

  defp valid_partial_range?(headers, <<_first_byte>>) do
    case header(headers, "content-range") do
      value when is_binary(value) -> String.match?(value, ~r/\Abytes 0-0\/[1-9][0-9]*\z/)
      _ -> false
    end
  end

  defp valid_partial_range?(_headers, _body), do: false

  defp decodable_asset?(:png, body), do: decodable_png?(body)
  defp decodable_asset?(:mp4, body), do: decodable_mp4?(body)

  defp decodable_png?(<<137, 80, 78, 71, 13, 10, 26, 10, chunks::binary>>) do
    case png_chunks(chunks, []) do
      {:ok, [{"IHDR", <<width::32, height::32, _rest::binary-size(5)>>} | _] = decoded} ->
        width > 0 and height > 0 and
          Enum.any?(decoded, &match?({"IDAT", data} when data != "", &1)) and
          List.last(decoded) == {"IEND", ""}

      _ ->
        false
    end
  end

  defp decodable_png?(_body), do: false

  defp png_chunks(<<>>, chunks), do: {:ok, Enum.reverse(chunks)}

  defp png_chunks(<<length::32, type::binary-size(4), rest::binary>>, chunks)
       when byte_size(rest) >= length + 4 do
    <<data::binary-size(length), crc::32, tail::binary>> = rest

    if :erlang.crc32(type <> data) == crc,
      do: png_chunks(tail, [{type, data} | chunks]),
      else: :error
  end

  defp png_chunks(_body, _chunks), do: :error

  defp decodable_mp4?(body) when is_binary(body) do
    case mp4_boxes(body, MapSet.new()) do
      {:ok, boxes} -> Enum.all?(["ftyp", "moov", "mdat"], &MapSet.member?(boxes, &1))
      :error -> false
    end
  end

  defp mp4_boxes(<<>>, boxes), do: {:ok, boxes}

  defp mp4_boxes(<<size::32, type::binary-size(4), rest::binary>>, boxes) do
    cond do
      size == 0 and byte_size(rest) > 0 ->
        {:ok, MapSet.put(boxes, type)}

      size == 1 and byte_size(rest) >= 8 ->
        <<extended::64, payload::binary>> = rest
        consume_mp4_box(extended, 16, type, payload, boxes)

      size >= 8 ->
        consume_mp4_box(size, 8, type, rest, boxes)

      true ->
        :error
    end
  end

  defp mp4_boxes(_body, _boxes), do: :error

  defp consume_mp4_box(size, header_size, type, rest, boxes)
       when size >= header_size and byte_size(rest) >= size - header_size do
    payload_size = size - header_size
    <<payload::binary-size(payload_size), tail::binary>> = rest

    if type != "ftyp" or byte_size(payload) >= 4,
      do: mp4_boxes(tail, MapSet.put(boxes, type)),
      else: :error
  end

  defp consume_mp4_box(_size, _header_size, _type, _rest, _boxes), do: :error

  defp asset_content_type(:png), do: "image/png"
  defp asset_content_type(:mp4), do: "video/mp4"

  defp content_type?(headers, expected) do
    case header(headers, "content-type") do
      value when is_binary(value) ->
        value |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase() ==
          expected

      _ ->
        false
    end
  end

  defp header(headers, name) when is_map(headers) do
    case Map.get(headers, name) do
      [value | _] when is_binary(value) -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp header(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) and is_binary(value) ->
        if String.downcase(key) == name, do: value

      _ ->
        nil
    end)
  end

  defp header(_headers, _name), do: nil

  defp get(client, url, headers \\ []) do
    client.get(url,
      connect_options: [timeout: 3_000],
      receive_timeout: 8_000,
      retry: false,
      decode_body: false,
      headers: headers
    )
  rescue
    _ -> {:error, :media_probe_failed}
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp boundary_uris?(uris, base_uri) when is_map(uris) do
    field(uris, :first) == base_uri <> Integer.to_string(RegentsClub.first_token_id()) and
      field(uris, :last) == base_uri <> Integer.to_string(RegentsClub.last_token_id())
  end

  defp boundary_uris?(_uris, _base_uri), do: false

  defp positive_integer_string?(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> true
      _ -> false
    end
  end

  defp positive_integer_string?(_value), do: false

  defp valid_hash?("0x" <> hash),
    do: byte_size(hash) == 64 and String.match?(hash, ~r/\A[0-9a-fA-F]+\z/)

  defp valid_hash?(_hash), do: false
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp chain_client,
    do:
      Application.get_env(
        :ash_platform,
        :regents_club_chain_client,
        AshPlatform.RegentsClub.RpcClient
      )
end
