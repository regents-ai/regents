defmodule AshPlatformWeb.RegentsClubMetadataLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.RegentsClub

  @owner "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
  @other "0x1111111111111111111111111111111111111111"
  @attempt "c56a4180-65aa-42ec-a945-5fd21dec0538"
  @hash "0x" <> String.duplicate("ab", 32)

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

  test "missing wallet hash consumes the attempt and communicates manual review", %{conn: conn} do
    owner = account!("owner-unknown", [@owner])
    {:ok, view, _html} = mount(conn, owner)
    render_async(view)

    render_hook(view, "prepare_regents_club_metadata", %{
      "address" => @owner,
      "attempt_id" => @attempt
    })

    assert_push_event(view, "regents-club-metadata:prepared", _payload)
    render_hook(view, "regents_club_metadata_submission_unknown", %{"attempt_id" => @attempt})
    assert render_async(view) =~ "Manual founder review is required"

    render_hook(view, "regents_club_metadata_submission_unknown", %{"attempt_id" => @attempt})
    assert render(view) =~ "Manual founder review is required"
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
