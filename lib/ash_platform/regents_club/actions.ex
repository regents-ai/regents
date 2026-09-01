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

  # Network work is deliberately completed before the short session transaction.
  # The transaction exists only to prove the browser session is still current.
  def deployment_readiness(lease) do
    with {:ok, snapshot} <- runtime_readiness(),
         :ok <- current_session(lease) do
      {:ok, snapshot}
    end
  end

  def observe_hash(envelope, hash), do: chain_client().observe(envelope, hash)
  def recover_unknown(envelope), do: chain_client().recover(envelope)

  def prepare(active_wallet, attempt_id, lease) do
    with true <- RegentsClub.enabled?(),
         true <- RegentsClub.valid_attempt_id?(attempt_id),
         {:ok, signer} <- Address.normalize(active_wallet),
         {:ok, %{state: :ready}} <- runtime_readiness(),
         {:ok, preflight} <- chain_client().prepare(),
         envelope <- envelope(attempt_id, signer, preflight),
         true <- valid_envelope?(envelope),
         :ok <- current_session(lease) do
      {:ok, envelope}
    else
      false -> {:error, :not_authorized}
      :error -> {:error, :not_authorized}
      {:error, reason} -> {:error, reason}
      _state -> {:error, :contract_state_mismatch}
    end
  end

  def valid_envelope?(envelope) do
    Envelope.valid?(envelope, validation(envelope)) and exact_envelope?(envelope)
  rescue
    _ -> false
  end

  def valid_observation_envelope?(envelope) do
    Envelope.valid_for_confirmation?(envelope, validation(envelope)) and exact_envelope?(envelope)
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

  defp current_session(%{lineage: lineage, account_id: account_id}) do
    callback = fn _account -> {:ok, :current} end

    case SessionAuthority.transact_lease(lineage, account_id, callback) do
      {:ok, :current} -> :ok
      {:error, :stale_authority} -> {:error, :session_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp current_session(_lease), do: {:error, :session_unavailable}

  defp runtime_readiness do
    with :ok <- public_privy_bootstrap(),
         :ok <- server_verifier(),
         true <- Application.get_env(:ash_platform, :regents_club_privy_origin_canary, false),
         :ok <- media_probes(),
         {:ok, snapshot} <- chain_client().status() do
      {:ok, snapshot}
    else
      false -> {:error, :privy_origin_canary_required}
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
    Enum.all?([
      field(envelope, :resource) == @resource,
      field(envelope, :action) == RegentsClub.action(),
      field(envelope, :chain_id) == RegentsClub.chain_id(),
      field(envelope, :to) == RegentsClub.contract_address(),
      field(envelope, :value) == "0",
      field(envelope, :data) == RegentsClub.calldata(),
      valid_signer?(field(envelope, :expected_signer)),
      field(envelope, :risk_copy) == @risk_copy
    ])
  end

  defp exact_arguments?(arguments) when is_map(arguments) do
    field(arguments, :new_base_uri) == RegentsClub.new_base_uri() and
      RegentsClub.valid_attempt_id?(field(arguments, :attempt_id))
  end

  defp exact_arguments?(_arguments), do: false

  defp exact_preflight?(metadata) when is_map(metadata) do
    anchor_number = field(metadata, :anchor_block_number)
    gas_estimate = field(metadata, :gas_estimate)

    Enum.all?([
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
    ])
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

  defp validation(envelope) do
    [
      to: RegentsClub.contract_address(),
      signer: field(envelope, :expected_signer),
      resource: @resource,
      contract_name: @contract_name,
      action: RegentsClub.action()
    ]
  end

  defp valid_signer?(signer) do
    case Address.normalize(signer) do
      {:ok, ^signer} -> true
      _ -> false
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

    defp release_manifest do
      case Application.get_env(:ash_platform, :regents_club_media_manifest_module) do
        module when is_atom(module) and not is_nil(module) ->
          if Code.ensure_loaded?(module) and function_exported?(module, :release_manifest, 0),
            do: module.release_manifest(),
            else: :error

        _other ->
          {:ok, RegentsClub.release_manifest()}
      end
    rescue
      _error -> :error
    end
  else
    defp media_probes, do: live_media_probes()

    defp release_manifest do
      {:ok, RegentsClub.release_manifest()}
    rescue
      _error -> :error
    end
  end

  defp live_media_probes do
    client = Application.get_env(:ash_platform, :regents_club_media_http_client, Req)

    with {:ok, release_manifest} <- release_manifest(),
         {:ok, %{status: 200, body: body}} <- get(client, @media_origin <> "/healthz"),
         true <- is_binary(body) and String.trim(body) == "ok",
         :ok <- verify_representative_tokens(client, release_manifest) do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp verify_representative_tokens(client, release_manifest) when is_map(release_manifest) do
    Enum.reduce_while(@representative_tokens, :ok, fn token_id, :ok ->
      verify_representative_token(client, release_manifest, token_id)
    end)
  end

  defp verify_representative_tokens(_client, _release_manifest),
    do: {:error, :media_probe_failed}

  defp verify_representative_token(client, release_manifest, token_id) do
    with {:ok, row} <- Map.fetch(release_manifest, token_id),
         :ok <- verify_live_token(client, row) do
      {:cont, :ok}
    else
      _error -> {:halt, {:error, :media_probe_failed}}
    end
  end

  defp verify_live_token(client, %{metadata: metadata, image: image, video: video}) do
    with {:ok, decoded} <-
           verified_body(
             client,
             @media_origin <> "/" <> metadata.path,
             metadata,
             "application/json"
           ),
         {:ok, document} when is_map(document) <- Jason.decode(decoded),
         true <- exact_asset_url?(document["image"], image.path),
         true <- exact_asset_url?(document["animation_url"], video.path),
         {:ok, _image} <-
           verified_body(client, @media_origin <> "/" <> image.path, image, "image/png"),
         {:ok, _video} <-
           verified_body(client, @media_origin <> "/" <> video.path, video, "video/mp4") do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp verified_body(client, url, expected, content_type) do
    with {:ok, %{status: 200, headers: headers, body: body}} <- get(client, url),
         true <- content_type?(headers, content_type),
         true <- header(headers, "content-length") in [nil, Integer.to_string(expected.bytes)],
         true <- is_binary(body) and byte_size(body) == expected.bytes,
         true <- sha256(body) == expected.sha256 do
      {:ok, body}
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp exact_asset_url?(url, expected_path) do
    case URI.new(url) do
      {:ok,
       %URI{
         scheme: "https",
         host: "media.regents.sh",
         userinfo: nil,
         path: path,
         query: nil,
         fragment: nil
       }}
      when is_binary(path) ->
        path == "/" <> expected_path and url == @media_origin <> "/" <> expected_path

      _ ->
        false
    end
  end

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

  defp get(client, url) do
    client.get(url,
      connect_options: [timeout: 3_000],
      receive_timeout: 8_000,
      retry: false,
      redirect: false,
      decode_body: false
    )
  rescue
    _ -> {:error, :media_probe_failed}
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp sha256(contents),
    do: :sha256 |> :crypto.hash(contents) |> Base.encode16(case: :lower)

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
