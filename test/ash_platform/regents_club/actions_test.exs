defmodule AshPlatform.RegentsClub.ActionsTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.Actions

  @owner "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
  @other "0x1111111111111111111111111111111111111111"
  @attempt "c56a4180-65aa-42ec-a945-5fd21dec0538"

  setup do
    keys = [
      :regents_club_metadata_cutover,
      :regents_club_chain_client,
      :test_regents_club_chain_responses,
      :regents_club_privy_origin_canary,
      :regents_club_media_full_corpus_attestation,
      :regents_club_media_probe_module,
      :privy,
      :privy_verifier
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:ash_platform, &1)})

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, true)

    Application.put_env(
      :ash_platform,
      :regents_club_chain_client,
      AshPlatform.TestRegentsClubChainClient
    )

    Application.put_env(:ash_platform, :privy, app_id: "public-test-id")
    Application.put_env(:ash_platform, :privy_verifier, AshPlatform.TestPrivyVerifier)
    Application.put_env(:ash_platform, :regents_club_privy_origin_canary, true)

    Application.put_env(
      :ash_platform,
      :regents_club_media_full_corpus_attestation,
      RegentsClub.media_release_attestation()["artifact_manifest_sha256"]
    )

    Application.put_env(
      :ash_platform,
      :regents_club_media_probe_module,
      AshPlatform.TestRegentsClubChainClient
    )

    Application.delete_env(:ash_platform, :test_regents_club_chain_responses)

    on_exit(fn -> Enum.each(previous, fn {key, value} -> restore(key, value) end) end)

    :ok
  end

  test "prepares only the exact reviewed action inside the current owner lease" do
    account = account!("owner", [@owner])

    assert {:ok, envelope} = Actions.prepare(@owner, @attempt, current_lease(account.id))
    assert envelope.arguments.attempt_id == @attempt
    assert is_binary(envelope.confirmation_token)
    assert envelope.action == "set_base_uri"
    assert envelope.chain_id == 8453
    assert envelope.to == RegentsClub.contract_address()
    assert envelope.value == "0"
    assert envelope.data == RegentsClub.calldata()
    assert envelope.expected_signer == RegentsClub.owner()
    assert envelope.metadata.anchor_block_number == 42
    assert envelope.metadata.current_base_uri == RegentsClub.old_base_uri()
    assert Actions.valid_envelope?(envelope)

    for changed <- [
          put_in(envelope, [:metadata, :gas_estimate], "0"),
          put_in(envelope, [:metadata, :boundary_token_uris, :last], RegentsClub.old_base_uri()),
          put_in(envelope, [:metadata, :owner_simulation], "unknown"),
          put_in(envelope, [:arguments, :attempt_id], "not-an-attempt"),
          Map.put(envelope, :risk_copy, "Different risk")
        ] do
      refute changed |> resign() |> Actions.valid_envelope?()
    end
  end

  test "fails closed for a disabled gate, a different signer, or a signer absent from linked wallets" do
    account = account!("owner", [@owner])
    lease = current_lease(account.id)

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, false)
    assert Actions.prepare(@owner, @attempt, lease) == {:error, :not_authorized}

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, true)
    assert Actions.prepare(@other, @attempt, lease) == {:error, :not_authorized}

    other = account!("other", [@other])
    assert Actions.prepare(@owner, @attempt, current_lease(other.id)) == {:error, :not_authorized}
  end

  test "rejects stale session authority before trusted preflight" do
    account = account!("stale", [@owner])
    lease = current_lease(account.id)
    assert is_binary(SessionAuthority.revoke(%{lineage: lease.lineage, generation: 1}))

    assert Actions.prepare(@owner, @attempt, lease) == {:error, :session_unavailable}
  end

  test "deployment readiness checks public bootstrap, verifier capability, and Base identity" do
    account = account!("readiness", [@owner])
    lease = current_lease(account.id)
    assert Actions.deployment_readiness(lease) == :ok

    Application.put_env(:ash_platform, :privy, app_id: "")
    assert Actions.deployment_readiness(lease) == {:error, :privy_unavailable}

    Application.put_env(:ash_platform, :privy, app_id: "public-test-id")

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      readiness: {:error, :wrong_chain}
    })

    assert Actions.deployment_readiness(lease) == {:error, :wrong_chain}

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{})
    Application.put_env(:ash_platform, :regents_club_privy_origin_canary, false)

    assert Actions.deployment_readiness(lease) ==
             {:error, :privy_origin_canary_required}
  end

  test "deployment readiness revalidates the owner lease and exact media attestations" do
    owner = account!("readiness-owner", [@owner])
    other = account!("readiness-other", [@other])

    assert Actions.deployment_readiness(current_lease(other.id)) == {:error, :not_authorized}

    lease = current_lease(owner.id)
    assert is_binary(SessionAuthority.revoke(%{lineage: lease.lineage, generation: 1}))
    assert Actions.deployment_readiness(lease) == {:error, :session_unavailable}

    current = current_lease(owner.id)
    Application.put_env(:ash_platform, :regents_club_media_full_corpus_attestation, "wrong")

    assert Actions.deployment_readiness(current) ==
             {:error, :media_full_corpus_attestation_required}

    Application.put_env(
      :ash_platform,
      :regents_club_media_full_corpus_attestation,
      RegentsClub.media_release_attestation()["artifact_manifest_sha256"]
    )

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      media_readiness: {:error, :media_probe_failed}
    })

    assert Actions.deployment_readiness(current) == {:error, :media_probe_failed}

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{})
    Application.put_env(:ash_platform, :privy_verifier, __MODULE__.MissingVerifier)

    assert Actions.deployment_readiness(current) == {:error, :privy_verifier_unavailable}
  end

  test "a signed envelope is not prepared when any authoritative preflight invariant drifts" do
    account = account!("preflight-drift", [@owner])

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      prepare: fn ->
        {:ok,
         %{
           anchor: %{number: 42, hash: "0x" <> String.duplicate("42", 32)},
           owner: RegentsClub.owner(),
           base_uri: RegentsClub.old_base_uri(),
           token_uris: %{
             first: RegentsClub.old_base_uri() <> "1",
             last: RegentsClub.old_base_uri() <> "1998"
           },
           total_supply: 1_997,
           erc4906_supported: true,
           owner_simulation: "success",
           non_owner_simulation: "revert",
           runtime_keccak256: RegentsClub.runtime_keccak256(),
           gas_estimate: 81_189
         }}
      end
    })

    assert Actions.prepare(@owner, @attempt, current_lease(account.id)) ==
             {:error, :not_authorized}
  end

  defp account!(suffix, wallets) do
    Accounts.register_verified!("did:privy:regents-club-#{suffix}", hd(wallets), wallets,
      actor: %System{}
    )
  end

  defp resign(envelope) do
    payload =
      envelope
      |> Map.take([
        :action_id,
        :idempotency_key,
        :resource,
        :action,
        :chain_id,
        :to,
        :value,
        :data,
        :expected_signer,
        :prepared_at,
        :preparation_nonce,
        :expires_at,
        :risk_copy,
        :approval,
        :arguments,
        :metadata
      ])
      |> Jason.encode!()
      |> Jason.decode!()

    token = Phoenix.Token.sign(AshPlatformWeb.Endpoint, "wallet-action", payload)
    Map.put(envelope, :confirmation_token, token)
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
