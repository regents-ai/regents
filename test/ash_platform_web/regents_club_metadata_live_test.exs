defmodule AshPlatformWeb.RegentsClubMetadataLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.RegentsClub

  @owner "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
  @other "0x1111111111111111111111111111111111111111"
  @attempt "c56a4180-65aa-42ec-a945-5fd21dec0538"
  @second_attempt "307b7802-8626-4b9f-9f7a-b9dcad9e31d4"
  @hash "0x" <> String.duplicate("ab", 32)

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

  test "route is absent from navigation and fails closed unless flag and owner account both match",
       %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/regents-club/metadata-cutover")

    other = account!("other", [@other])
    assert {:error, {:redirect, %{to: "/"}}} = mount(conn, other)

    owner = account!("owner-disabled", [@owner])
    Application.put_env(:ash_platform, :regents_club_metadata_cutover, false)
    assert {:error, {:redirect, %{to: "/"}}} = mount(conn, owner)
  end

  test "owner prepares only the fixed envelope and finalized observation closes the node gate", %{
    conn: conn
  } do
    owner = account!("owner-flow", [@owner])
    {:ok, view, _html} = mount(conn, owner)
    assert render_async(view) =~ "Reviewed cutover"

    render_hook(view, "regents_club_metadata_active_wallet", %{"address" => @owner})

    render_hook(view, "prepare_regents_club_metadata", %{
      "address" => @owner,
      "attempt_id" => @attempt
    })

    review = render(view)
    assert review =~ "Confirm the exact reviewed transaction"
    assert review =~ RegentsClub.calldata_keccak256()
    assert review =~ "No prepared rollback exists"
    refute_push_event(view, "regents-club-metadata:prepared", _payload)

    render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})

    assert_push_event(view, "regents-club-metadata:prepared", %{
      attempt_id: @attempt,
      envelope: envelope
    })

    assert envelope.to == RegentsClub.contract_address()
    assert envelope.value == "0"
    assert envelope.data == RegentsClub.calldata()

    render_hook(view, "regents_club_metadata_submitted", %{
      "attempt_id" => @attempt,
      "hash" => @hash
    })

    assert render_async(view) =~ "Cutover finalized and this route is closed"
    refute RegentsClub.enabled?()
  end

  test "two deliberate attempt IDs receive independent wallet handoffs", %{conn: conn} do
    owner = account!("owner-independent", [@owner])
    {:ok, view, _html} = mount(conn, owner)
    render_async(view)
    render_hook(view, "regents_club_metadata_active_wallet", %{"address" => @owner})

    for attempt_id <- [@attempt, @second_attempt] do
      render_hook(view, "prepare_regents_club_metadata", %{
        "address" => @owner,
        "attempt_id" => attempt_id
      })

      assert render(view) =~ "Confirm the exact reviewed transaction"
      render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => attempt_id})

      assert_push_event(view, "regents-club-metadata:prepared", %{
        attempt_id: ^attempt_id,
        envelope: envelope
      })

      assert envelope.arguments.attempt_id == attempt_id
    end

    assert render(view) =~ "Review another independent attempt"
  end

  test "unknown submission recovery is bounded and never reopens a send", %{conn: conn} do
    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      recover: {:ok, :pending}
    })

    owner = account!("owner-bounded-recovery", [@owner])
    {:ok, view, _html} = mount(conn, owner)
    render_async(view)

    render_hook(view, "prepare_regents_club_metadata", %{
      "address" => @owner,
      "attempt_id" => @attempt
    })

    render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})
    assert_push_event(view, "regents-club-metadata:prepared", _payload)
    render_hook(view, "regents_club_metadata_submission_unknown", %{"attempt_id" => @attempt})
    render_async(view)

    for _poll <- 1..41 do
      send(view.pid, {:observe_regents_club_metadata, @attempt})
      render_async(view)
    end

    assert render(view) =~ "Manual founder review is required"
    refute_push_event(view, "regents-club-metadata:prepared", _payload)
  end

  test "missing wallet hash consumes the attempt and communicates manual review", %{conn: conn} do
    owner = account!("owner-unknown", [@owner])
    {:ok, view, _html} = mount(conn, owner)
    render_async(view)

    render_hook(view, "prepare_regents_club_metadata", %{
      "address" => @owner,
      "attempt_id" => @attempt
    })

    render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})
    assert_push_event(view, "regents-club-metadata:prepared", _payload)
    render_hook(view, "regents_club_metadata_submission_unknown", %{"attempt_id" => @attempt})
    assert render_async(view) =~ "Manual founder review is required"

    render_hook(view, "regents_club_metadata_submission_unknown", %{"attempt_id" => @attempt})
    assert render(view) =~ "Manual founder review is required"
  end

  test "new URI without exact finalized transaction evidence requires manual review", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      status: {:ok, %{state: :changed_unverified}}
    })

    owner = account!("owner-changed", [@owner])
    {:ok, view, _html} = mount(conn, owner)
    assert render_async(view) =~ "has no exact finalized transaction evidence"
    refute render(view) =~ "Review in owner wallet"
    assert RegentsClub.enabled?()
  end

  defp mount(conn, account) do
    conn
    |> init_test_session(%{human_account_id: account.id})
    |> live("/regents-club/metadata-cutover")
  end

  defp account!(suffix, wallets) do
    Accounts.register_verified!("did:privy:regents-club-live-#{suffix}", hd(wallets), wallets,
      actor: %System{}
    )
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
