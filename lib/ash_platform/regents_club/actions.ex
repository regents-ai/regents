defmodule AshPlatform.RegentsClub.Actions do
  @moduledoc false

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.RegentsClub
  alias AshPlatform.WalletActions.Address

  @ttl_seconds 180

  def deployment_readiness do
    with :ok <- public_privy_bootstrap(),
         :ok <- server_verifier(),
         :ok <- chain_client().readiness() do
      :ok
    end
  end

  def status, do: chain_client().status()

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

  def observe_hash(envelope, hash), do: chain_client().observe(envelope, hash)
  def recover_unknown(envelope), do: chain_client().recover(envelope)

  defp prepare_current(account, signer, attempt_id) do
    with true <- RegentsClub.authorized_account?(account),
         true <- signer == RegentsClub.owner(),
         :ok <- deployment_readiness(),
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
    prepared_at = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      attempt_id: attempt_id,
      action: RegentsClub.action(),
      chain_id: RegentsClub.chain_id(),
      to: RegentsClub.contract_address(),
      value: "0",
      data: RegentsClub.calldata(),
      expected_signer: signer,
      prepared_at: DateTime.to_iso8601(prepared_at),
      expires_at: DateTime.add(prepared_at, @ttl_seconds, :second) |> DateTime.to_iso8601(),
      risk_copy:
        "Replace the Regents Club metadata base URI for tokens 1 through 1998. This is the one reviewed forward cutover.",
      metadata: %{
        anchor_block_number: preflight.anchor.number,
        anchor_block_hash: preflight.anchor.hash,
        current_base_uri: preflight.base_uri,
        gas_estimate: Integer.to_string(preflight.gas_estimate),
        runtime_keccak256: preflight.runtime_keccak256
      }
    }
  end

  def valid_envelope?(envelope) do
    with true <- valid_observation_envelope?(envelope),
         :gt <- DateTime.compare(parse_time!(envelope.expires_at), DateTime.utc_now()) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_observation_envelope?(envelope) do
    with true <- envelope.action == RegentsClub.action(),
         true <- envelope.chain_id == RegentsClub.chain_id(),
         true <- envelope.to == RegentsClub.contract_address(),
         true <- envelope.value == "0",
         true <- envelope.data == RegentsClub.calldata(),
         true <- envelope.expected_signer == RegentsClub.owner(),
         true <- envelope.metadata.current_base_uri == RegentsClub.old_base_uri(),
         true <- envelope.metadata.runtime_keccak256 == RegentsClub.runtime_keccak256(),
         true <- RegentsClub.valid_attempt_id?(envelope.attempt_id),
         {:ok, prepared_at, _} <- DateTime.from_iso8601(envelope.prepared_at),
         {:ok, expires_at, _} <- DateTime.from_iso8601(envelope.expires_at),
         true <- DateTime.diff(expires_at, prepared_at, :second) == @ttl_seconds do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp parse_time!(value) do
    {:ok, parsed, _} = DateTime.from_iso8601(value)
    parsed
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

    production_key? = verifier != AshPlatform.Privy or present?(config[:verification_key])

    if capable? and production_key?, do: :ok, else: {:error, :privy_verifier_unavailable}
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp chain_client,
    do:
      Application.get_env(
        :ash_platform,
        :regents_club_chain_client,
        AshPlatform.RegentsClub.RpcClient
      )
end
