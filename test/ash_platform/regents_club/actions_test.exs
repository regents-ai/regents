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
    Application.delete_env(:ash_platform, :test_regents_club_chain_responses)

    on_exit(fn -> Enum.each(previous, fn {key, value} -> restore(key, value) end) end)

    :ok
  end

  test "prepares only the exact reviewed action inside the current owner lease" do
    account = account!("owner", [@owner])

    assert {:ok, envelope} = Actions.prepare(@owner, @attempt, current_lease(account.id))
    assert envelope.attempt_id == @attempt
    assert envelope.action == "set_base_uri"
    assert envelope.chain_id == 8453
    assert envelope.to == RegentsClub.contract_address()
    assert envelope.value == "0"
    assert envelope.data == RegentsClub.calldata()
    assert envelope.expected_signer == RegentsClub.owner()
    assert envelope.metadata.anchor_block_number == 42
    assert envelope.metadata.current_base_uri == RegentsClub.old_base_uri()
    assert Actions.valid_envelope?(envelope)
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
    assert Actions.deployment_readiness() == :ok

    Application.put_env(:ash_platform, :privy, app_id: "")
    assert Actions.deployment_readiness() == {:error, :privy_unavailable}

    Application.put_env(:ash_platform, :privy, app_id: "public-test-id")

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      readiness: {:error, :wrong_chain}
    })

    assert Actions.deployment_readiness() == {:error, :wrong_chain}
  end

  defp account!(suffix, wallets) do
    Accounts.register_verified!("did:privy:regents-club-#{suffix}", hd(wallets), wallets,
      actor: %System{}
    )
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
