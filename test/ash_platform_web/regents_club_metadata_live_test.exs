defmodule AshPlatformWeb.RegentsClubMetadataLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.RegentsClub

  @owner "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
  @other "0x1111111111111111111111111111111111111111"
  @selected "0x2222222222222222222222222222222222222222"
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
      :wallet_action_clock,
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
      RegentsClub.media_release_attestation()["release_manifest_sha256"]
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

  test "route is absent from navigation and admits any authenticated account only while enabled",
       %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/regents-club/metadata-cutover")

    other = account!("other", [@other])
    assert {:ok, view, _html} = mount(conn, other)
    assert render_async(view) =~ "Reviewed cutover"
    assert render(view) =~ "Select an Ethereum wallet in Privy before continuing"

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, false)
    disabled = account!("authenticated-disabled", [@other])
    assert {:error, {:redirect, %{to: "/"}}} = mount(conn, disabled)
  end

  test "selected wallet prepares only the fixed envelope and finalized observation closes the node gate",
       %{
         conn: conn
       } do
    account = account!("selected-wallet-flow", [@other])
    {:ok, view, _html} = mount(conn, account)
    assert render_async(view) =~ "Reviewed cutover"

    render_hook(view, "regents_club_metadata_active_wallet", %{"address" => @selected})
    assert render(view) =~ String.downcase(@selected)
    assert render(view) =~ "website does not pre-authorize"

    render_hook(view, "prepare_regents_club_metadata", %{
      "address" => @selected,
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
    assert envelope.expected_signer == String.downcase(@selected)
    refute envelope.expected_signer == String.downcase(@owner)

    render_hook(view, "regents_club_metadata_submitted", %{
      "attempt_id" => @attempt,
      "hash" => @hash
    })

    assert render_async(view) =~ "Cutover finalized and this route is closed"
    refute RegentsClub.enabled?()
  end

  test "two deliberate attempt IDs receive independent wallet handoffs", %{conn: conn} do
    account = account!("selected-independent", [@other])
    {:ok, view, _html} = mount(conn, account)
    render_async(view)
    render_hook(view, "regents_club_metadata_active_wallet", %{"address" => @selected})

    for attempt_id <- [@attempt, @second_attempt] do
      render_hook(view, "prepare_regents_club_metadata", %{
        "address" => @selected,
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

  test "confirmation replaces the reviewed envelope with a freshly revalidated anchor", %{
    conn: conn
  } do
    {:ok, counter} = Agent.start_link(fn -> 41 end)
    on_exit(fn -> if Process.alive?(counter), do: Agent.stop(counter) end)

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      prepare: fn ->
        anchor = Agent.get_and_update(counter, &{&1, &1 + 1})
        {:ok, preflight(anchor)}
      end
    })

    account = account!("selected-fresh-confirm", [@other])
    {:ok, view, _html} = mount(conn, account)
    render_async(view)
    render_hook(view, "regents_club_metadata_active_wallet", %{"address" => @selected})

    render_hook(view, "prepare_regents_club_metadata", %{
      "address" => @selected,
      "attempt_id" => @attempt
    })

    assert render(view) =~ "41 <code>"
    render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})

    assert_push_event(view, "regents-club-metadata:prepared", %{
      attempt_id: @attempt,
      envelope: fresh
    })

    assert fresh.metadata.anchor_block_number == 42
    assert fresh.arguments.attempt_id == @attempt
  end

  test "flag, media, and preflight drift after review each refuse wallet handoff", %{conn: conn} do
    for {suffix, drift} <- [
          {"flag",
           fn -> Application.put_env(:ash_platform, :regents_club_metadata_cutover, false) end},
          {"media",
           fn ->
             Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
               media_readiness: {:error, :media_probe_failed}
             })
           end},
          {"preflight",
           fn ->
             Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
               prepare: {:error, :contract_state_mismatch}
             })
           end}
        ] do
      Application.put_env(:ash_platform, :regents_club_metadata_cutover, true)
      Application.delete_env(:ash_platform, :test_regents_club_chain_responses)

      account = account!("confirm-drift-#{suffix}", [@other])
      {:ok, view, _html} = mount(conn, account)
      render_async(view)
      prepare_review(view, @attempt)
      drift.()

      render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})
      assert_push_event(view, "regents-club-metadata:refused", %{attempt_id: @attempt})
      refute_push_event(view, "regents-club-metadata:prepared", _payload)
      assert render(view) =~ "Nothing was sent"
    end
  end

  test "confirmation revalidates the current account and session lease", %{conn: conn} do
    account = account!("confirm-current-account", [@other])
    signed_conn = init_test_session(conn, %{human_account_id: account.id})
    {:ok, view, _html} = live(signed_conn, "/regents-club/metadata-cutover")
    render_async(view)
    prepare_review(view, @attempt)

    assert {:ok, _lapsed} = Accounts.refresh_verified(account, nil, [], actor: %System{})

    render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})
    assert has_element?(view, "#account-control [data-account-target=sign-in]")
    refute_push_event(view, "regents-club-metadata:prepared", _payload)

    second_account = account!("confirm-revoked-session", [@other])
    second_conn = init_test_session(build_conn(), %{human_account_id: second_account.id})
    {:ok, second_view, _html} = live(second_conn, "/regents-club/metadata-cutover")
    render_async(second_view)
    prepare_review(second_view, @second_attempt)

    assert SessionAuthority.revoke(second_conn |> get_session() |> SessionAuthority.claim())
    render_hook(second_view, "confirm_regents_club_metadata", %{"attempt_id" => @second_attempt})
    assert has_element?(second_view, "#account-control [data-account-target=sign-in]")
    refute_push_event(second_view, "regents-club-metadata:prepared", _payload)
  end

  test "confirmation refuses when the selected wallet changes after review", %{conn: conn} do
    account = account!("confirm-wallet-drift", [@other])
    {:ok, view, _html} = mount(conn, account)
    render_async(view)
    prepare_review(view, @attempt)

    render_hook(view, "regents_club_metadata_active_wallet", %{"address" => @other})
    render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})

    assert_push_event(view, "regents-club-metadata:refused", %{attempt_id: @attempt})
    refute_push_event(view, "regents-club-metadata:prepared", _payload)
    assert render(view) =~ "selected Privy wallet changed after review"
    assert render(view) =~ "Nothing was sent"
  end

  test "finality observation continues beyond forty polls and never reopens a send", %{conn: conn} do
    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      observe: {:ok, :pending}
    })

    account = account!("selected-delayed-finality", [@other])
    {:ok, view, _html} = mount(conn, account)
    render_async(view)
    prepare_review(view, @attempt)
    render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})
    assert_push_event(view, "regents-club-metadata:prepared", _payload)

    render_hook(view, "regents_club_metadata_submitted", %{
      "attempt_id" => @attempt,
      "hash" => @hash
    })

    render_async(view)

    for _poll <- 1..41 do
      send(view.pid, {:observe_regents_club_metadata, @attempt})
      render_async(view)
    end

    refute render(view) =~ "Manual founder review is required"
    assert render(view) =~ "Review another independent attempt"
    refute_push_event(view, "regents-club-metadata:prepared", _payload)

    Application.delete_env(:ash_platform, :test_regents_club_chain_responses)
    send(view.pid, {:observe_regents_club_metadata, @attempt})
    assert render_async(view) =~ "Cutover finalized and this route is closed"
  end

  test "fresh handoff deadline becomes unknown without another wallet request", %{conn: conn} do
    prepared_at = ~U[2026-08-31 12:00:00Z]
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> prepared_at end)

    account = account!("selected-deadline", [@other])
    {:ok, view, _html} = mount(conn, account)
    render_async(view)
    prepare_review(view, @attempt)
    render_hook(view, "confirm_regents_club_metadata", %{"attempt_id" => @attempt})
    assert_push_event(view, "regents-club-metadata:prepared", _payload)

    Application.put_env(:ash_platform, :wallet_action_clock, fn ->
      DateTime.add(prepared_at, 45 * 60, :second)
    end)

    render_hook(view, "regents_club_metadata_submitted", %{
      "attempt_id" => @attempt,
      "hash" => @hash
    })

    assert render(view) =~ "Manual founder review is required"
    refute_push_event(view, "regents-club-metadata:prepared", _payload)
  end

  test "missing wallet hash consumes the attempt and communicates manual review", %{conn: conn} do
    account = account!("selected-unknown", [@other])
    {:ok, view, _html} = mount(conn, account)
    render_async(view)
    prepare_review(view, @attempt)

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

    account = account!("selected-changed", [@other])
    {:ok, view, _html} = mount(conn, account)
    assert render_async(view) =~ "has no exact finalized transaction evidence"
    refute render(view) =~ "Review with selected wallet"
    assert RegentsClub.enabled?()
  end

  defp mount(conn, account) do
    conn
    |> init_test_session(%{human_account_id: account.id})
    |> live("/regents-club/metadata-cutover")
  end

  defp prepare_review(view, attempt_id, wallet \\ @selected) do
    render_hook(view, "regents_club_metadata_active_wallet", %{"address" => wallet})

    render_hook(view, "prepare_regents_club_metadata", %{
      "address" => wallet,
      "attempt_id" => attempt_id
    })

    assert render(view) =~ "Confirm the exact reviewed transaction"
  end

  defp preflight(anchor) do
    %{
      anchor: %{
        number: anchor,
        hash: "0x" <> String.pad_leading(Integer.to_string(anchor, 16), 64, "0")
      },
      owner: RegentsClub.owner(),
      base_uri: RegentsClub.old_base_uri(),
      token_uris: %{
        first: RegentsClub.old_base_uri() <> "1",
        last: RegentsClub.old_base_uri() <> "1998"
      },
      total_supply: 1998,
      erc4906_supported: true,
      owner_simulation: "success",
      non_owner_simulation: "revert",
      runtime_keccak256: RegentsClub.runtime_keccak256(),
      gas_estimate: 81_189
    }
  end

  defp account!(suffix, wallets) do
    Accounts.register_verified!("did:privy:regents-club-live-#{suffix}", hd(wallets), wallets,
      actor: %System{}
    )
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
