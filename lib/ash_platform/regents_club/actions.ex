defmodule AshPlatform.RegentsClub.Actions do
  @moduledoc false

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.RegentsClub
  alias AshPlatform.WalletActions.{Address, Envelope}

  @resource "regents_club_metadata"
  @contract_name "RegentsClub"
  @risk_copy "Collection-wide metadata cutover for Regents Club tokens 1 through 1998. No prepared rollback exists."

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
    Envelope.new(RegentsClub.action(), signer, RegentsClub.calldata(),
      to: RegentsClub.contract_address(),
      resource: @resource,
      contract_name: @contract_name,
      risk_copy: @risk_copy,
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
        calldata_keccak256: RegentsClub.calldata_keccak256()
      }
    )
  end

  defp exact_envelope?(envelope) do
    exact_transaction?(envelope) and
      exact_arguments?(field(envelope, :arguments)) and
      exact_preflight?(field(envelope, :metadata))
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
    expected = RegentsClub.media_release_attestation()["artifact_manifest_sha256"]

    if Application.get_env(:ash_platform, :regents_club_media_full_corpus_attestation) == expected,
      do: :ok,
      else: {:error, :media_full_corpus_attestation_required}
  end

  defp media_probes do
    case Application.get_env(:ash_platform, :regents_club_media_probe_module) do
      module when is_atom(module) ->
        if Code.ensure_loaded?(module) and function_exported?(module, :media_readiness, 0),
          do: module.media_readiness(),
          else: {:error, :media_probe_failed}

      _ ->
        live_media_probes()
    end
  end

  defp live_media_probes do
    client = Application.get_env(:ash_platform, :regents_club_media_http_client, Req)

    with {:ok, %{status: 200, body: body}} <- get(client, "https://media.regents.sh/healthz"),
         true <- is_binary(body) and String.trim(body) == "ok",
         :ok <- representative_media(client, 1),
         :ok <- representative_media(client, 1998) do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp representative_media(client, token_id) do
    with {:ok, %{status: 200, body: metadata}} <-
           get(client, "https://media.regents.sh/metadata/#{token_id}"),
         image when is_binary(image) <- metadata["image"],
         animation when is_binary(animation) <- metadata["animation_url"],
         :ok <- representative_asset(client, image),
         :ok <- representative_asset(client, animation) do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp representative_asset(client, url) do
    with {:ok, %URI{scheme: "https", host: "media.regents.sh"}} <- URI.new(url),
         {:ok, %{status: 200, body: asset}} <- get(client, url),
         true <- is_binary(asset) and byte_size(asset) > 0 do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp get(client, url) do
    client.get(url,
      connect_options: [timeout: 3_000],
      receive_timeout: 8_000,
      retry: false
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
