defmodule AshPlatformWeb.RedeemLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatformWeb.ShellLive

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"

  defmodule GatedChainClient do
    @behaviour AshPlatform.Redemption.ChainClient

    @impl true
    def overview(wallet, collection, token_id) do
      if test_pid = Application.get_env(:ash_platform, :test_redemption_read_gate) do
        send(test_pid, {:redemption_read_waiting, self()})

        receive do
          :continue_redemption_read -> :ok
        after
          5_000 -> raise "timed out waiting to continue the redemption read"
        end
      end

      case Application.get_env(:ash_platform, :test_redemption_read_result, :ok) do
        :ok -> AshPlatform.TestRedemptionChainClient.overview(wallet, collection, token_id)
        :error -> {:error, :provider_failure}
      end
    end
  end

  setup do
    on_exit(fn ->
      for key <- [
            :test_open_sea_handler,
            :test_open_sea_responses,
            :test_open_sea_watcher,
            :test_redemption_nft_approved,
            :test_redemption_nft_owner,
            :test_redemption_owner_unavailable,
            :test_redemption_read_gate,
            :test_redemption_read_result,
            :test_redemption_usdc_allowance,
            :test_redemption_usdc_balance
          ] do
        Application.delete_env(:ash_platform, key)
      end
    end)

    :ok
  end

  test "PUBLIC_FACTS: anonymous visitors see fixed facts and no wallet action", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/redeem")
    html = render_async(view)

    assert has_element?(
             view,
             "#redeem-intro-title",
             "See Animata Collection I and II on OpenSea"
           )

    assert has_element?(
             view,
             ~s(a[href="https://opensea.io/collection/animata"][target="_blank"][rel="noopener noreferrer"]),
             "Animata I"
           )

    assert has_element?(
             view,
             ~s(a[href="https://opensea.io/collection/regent-animata-ii"][target="_blank"][rel="noopener noreferrer"]),
             "Animata II"
           )

    assert has_element?(
             view,
             ~s(a[href="https://opensea.io/collection/regents-club"][target="_blank"][rel="noopener noreferrer"]),
             "seen here"
           )

    assert has_element?(
             view,
             "#redeem-intro .redeem-intro-copy p",
             "Animata I and II NFTs can be redeemed, along with 80 USDC, for 5,000,000 REGENT. You will also receive a membership NFT in the Regents Club, seen here."
           )

    assert has_element?(
             view,
             ~s(#redeem-intro-media video[autoplay][muted][loop][playsinline][poster="/images/redeem/animata1and2-poster.jpg"])
           )

    assert has_element?(
             view,
             ~s(img.redeem-intro-poster[src="/images/redeem/animata1and2-poster.jpg"])
           )

    assert html =~ "Redeem Animata"
    assert html =~ "80 USDC"
    assert html =~ "5,000,000 REGENT"
    assert html =~ "7 days"

    assert has_element?(
             view,
             ~s(#redemption-result-dialog[aria-labelledby="redemption-result-heading"])
           )

    assert has_element?(
             view,
             ~s(#redemption-result-dialog a[data-redemption-result-link][target="_blank"][rel="noopener noreferrer"])
           )

    refute has_element?(view, "[phx-click=prepare_redemption]")
  end

  test "REDEEM_ROUTE_OWNERSHIP: redemption events are inert outside /redeem", %{conn: conn} do
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    {:ok, view, _html} = live(conn, "/stake")

    for {event, params} <- [
          {"redemption_active_wallet", %{"address" => @wallet}},
          {"redemption_selection_changed", %{"collection" => "animata_i", "token_id" => "42"}},
          {"prepare_redemption", %{"action" => "claim", "attempt_id" => "outside-route"}},
          {"refresh_redemption", %{}},
          {"select_owned_animata", %{"collection" => "animata_i", "token-id" => "42"}}
        ] do
      render_hook(view, event, params)
    end

    refute_receive {:redemption_read_waiting, _}
    refute_push_event(view, "redemption:wallet-action", _)
  end

  test "ACTIVE_WALLET_ONLY: private facts require the published linked wallet", %{conn: conn} do
    account = register("redeem-wallet", [@wallet])
    view = mount_redeem(conn, account)
    render_async(view)
    assert has_element?(view, "button[data-redeem-connect]")

    activate(view, @other)
    render_async(view)
    assert render_async(view) =~ "not one of the wallets on your Regent account"
    refute has_element?(view, "#redemption-selection")

    activate(view, @wallet)
    assert render(view) =~ "Claimable REGENT"
    assert render(view) =~ "1 REGENT"
  end

  test "CURRENT_NEXT_STEP: only Base's current action is exposed", %{conn: conn} do
    view = conn |> signed_in("redeem-steps") |> activate(@wallet)
    select(view, "animata_i", "42")
    assert has_element?(view, ".redeem-next-step button", "Redeem")
    refute has_element?(view, ".redeem-next-step button", "Approve NFT")

    Application.put_env(:ash_platform, :test_redemption_nft_approved, false)
    view |> element(~s(button[phx-click="refresh_redemption"])) |> render_click()
    render_async(view)
    assert has_element?(view, ".redeem-next-step button", "Approve NFT")

    Application.put_env(:ash_platform, :test_redemption_nft_approved, true)
    Application.put_env(:ash_platform, :test_redemption_usdc_allowance, 0)
    view |> element(~s(button[phx-click="refresh_redemption"])) |> render_click()
    render_async(view)
    assert has_element?(view, ".redeem-next-step button", "Approve 80 USDC")
  end

  test "SELECTION_FAILURE: prior facts remain visible but selection actions stay disabled", %{
    conn: conn
  } do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, GatedChainClient)

    on_exit(fn ->
      Application.put_env(:ash_platform, :redemption_chain_client, previous_client)
    end)

    view = conn |> signed_in("redeem-selection-failure") |> activate(@wallet)
    select(view, "animata_i", "42")
    assert has_element?(view, ".redeem-next-step button:not([disabled])", "Redeem")

    Application.put_env(:ash_platform, :test_redemption_read_result, :error)

    view
    |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => "43"})
    |> render_change()

    render_async(view)

    assert has_element?(view, ".redeem-summary", "Base safe block 1,234")
    assert has_element?(view, ".redeem-next-step button[disabled]")
    assert has_element?(view, ~s|button[data-redemption-action="claim"]:not([disabled])|)
    assert render(view) =~ "Refresh failed"

    render_hook(view, "prepare_redemption", %{
      "action" => "redeem",
      "attempt_id" => "stale-selection"
    })

    refute_push_event(view, "redemption:wallet-action", _)
    assert_push_event(view, "redemption:wallet-refusal", %{attempt_id: "stale-selection"})

    Application.put_env(:ash_platform, :test_redemption_read_result, :ok)
    assert has_element?(view, ~s|button[data-redemption-action="claim"]:not([disabled])|)

    render_hook(view, "prepare_redemption", %{
      "action" => "claim",
      "attempt_id" => "account-wide-claim"
    })

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "account-wide-claim",
      envelope: %{action: "claim", expected_signer: @wallet}
    })
  end

  test "REFRESH_FEEDBACK: unchanged data is acknowledged and a later snapshot updates stats", %{
    conn: conn
  } do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, GatedChainClient)

    on_exit(fn ->
      Application.put_env(:ash_platform, :redemption_chain_client, previous_client)
    end)

    Application.put_env(:ash_platform, :test_redemption_usdc_balance, 80_000_000)
    view = conn |> signed_in("redeem-refresh") |> activate(@wallet)
    select(view, "animata_i", "42")

    assert has_element?(
             view,
             ".redeem-summary .redeem-metric:first-child",
             "80 USDC"
           )

    assert has_element?(
             view,
             ".redeem-summary .redeem-metric:last-child",
             "Base safe block 1,234"
           )

    assert has_element?(
             view,
             ~s(#redemption-refresh-status[data-visible="false"][aria-hidden="true"])
           )

    refute render(view) =~ "Refresh complete. Data is current"

    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    view |> element("#redemption-refresh") |> render_click()
    assert_receive {:redemption_read_waiting, read}

    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "80 USDC")

    assert has_element?(
             view,
             ".redeem-summary .redeem-metric:last-child",
             "Base safe block 1,234"
           )

    assert has_element?(view, ".redeem-summary")
    refute has_element?(view, ".redeem-status[aria-busy=true]")
    assert has_element?(view, ".redeem-next-step button:not([disabled])")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)

    assert has_element?(
             view,
             ~s(#redemption-refresh-status[data-visible="true"][aria-hidden="false"][role="status"][aria-live="polite"][aria-atomic="true"]),
             "Refresh complete. Data is current at Base safe block 1,234."
           )

    Application.put_env(:ash_platform, :test_redemption_usdc_balance, 125_000_000)
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    view |> element("#redemption-refresh") |> render_click()
    assert_receive {:redemption_read_waiting, read}

    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "80 USDC")
    refute has_element?(view, ".redeem-summary .redeem-metric:first-child", "125 USDC")
    assert has_element?(view, ".redeem-summary")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    refute render(view) =~ "Refresh complete. Data is current"
    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)

    assert has_element?(
             view,
             ".redeem-summary .redeem-metric:first-child",
             "125 USDC"
           )

    assert has_element?(
             view,
             ".redeem-summary .redeem-metric:last-child",
             "Base safe block 1,234"
           )

    Application.put_env(:ash_platform, :test_redemption_read_result, :error)
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    view |> element("#redemption-refresh") |> render_click()
    assert_receive {:redemption_read_waiting, read}
    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "125 USDC")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    refute render(view) =~ "Refresh complete. Data is current"
    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)

    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "125 USDC")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    assert render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."

    Application.put_env(:ash_platform, :test_redemption_read_result, :ok)
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    view |> element("#redemption-refresh") |> render_click()
    assert_receive {:redemption_read_waiting, read}
    refute render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."
    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "125 USDC")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)

    refute render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."

    assert has_element?(
             view,
             ~s(#redemption-refresh-status[data-visible="true"]),
             "Refresh complete. Data is current at Base safe block 1,234."
           )
  end

  test "DIRECT_REDEEM: each eligible click pushes one fresh envelope with no lifecycle UI", %{
    conn: conn
  } do
    view = conn |> signed_in("redeem-direct") |> activate(@wallet)
    select(view, "animata_i", "42")

    render_hook(view, "prepare_redemption", %{
      "action" => "redeem",
      "attempt_id" => "redeem-attempt-1"
    })

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "redeem-attempt-1",
      envelope: first
    })

    assert first.action == "redeem"
    assert first.expected_signer == @wallet

    Application.put_env(:ash_platform, :test_redemption_nft_owner, @other)

    render_hook(view, "prepare_redemption", %{
      "action" => "redeem",
      "attempt_id" => "refused-attempt"
    })

    assert_push_event(view, "redemption:wallet-refusal", %{attempt_id: "refused-attempt"})
    refute_push_event(view, "redemption:wallet-action", %{attempt_id: "refused-attempt"})

    Application.delete_env(:ash_platform, :test_redemption_nft_owner)

    render_hook(view, "prepare_redemption", %{
      "action" => "redeem",
      "attempt_id" => "redeem-attempt-2"
    })

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "redeem-attempt-2",
      envelope: second
    })

    refute first.action_id == second.action_id

    html = render(view)

    for retired <- ["Review before signing", "Submitted transaction", "transaction hash", "Retry"] do
      refute html =~ retired
    end
  end

  test "CLAIM_DIRECTLY: unlocked REGENT is its own exact control", %{conn: conn} do
    view = conn |> signed_in("redeem-claim") |> activate(@wallet)
    assert has_element?(view, ~s|button[data-redemption-action="claim"]:not([disabled])|)

    render_hook(view, "prepare_redemption", %{
      "action" => "claim",
      "attempt_id" => "claim-attempt"
    })

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "claim-attempt",
      envelope: %{action: "claim", expected_signer: @wallet}
    })

    assert has_element?(view, "button", "Claim unlocked REGENT")
  end

  test "OPENSEA_IS_CONVENIENCE: owned Animata fills selection and manual fields remain", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_open_sea_handler, fn url ->
      body =
        cond do
          String.contains?(url, "collection=animata&") ->
            %{"nfts" => [%{"identifier" => "42"}]}

          String.contains?(url, "collection=regents-club&") ->
            %{"nfts" => [%{"identifier" => "1123"}]}

          true ->
            %{"nfts" => []}
        end

      {:ok, %{status: 200, body: body}}
    end)

    view = conn |> signed_in("redeem-owned") |> activate(@wallet)
    render_async(view)
    assert has_element?(view, ".redeem-owned-list button", "Animata I #42")

    assert has_element?(
             view,
             ~s(.redeem-owned-list a[target="_blank"][rel="noopener noreferrer"]),
             "Regents Club #1123"
           )

    view |> element(".redeem-owned-list button", "Animata I #42") |> render_click()
    render_async(view)
    assert has_element?(view, ~s(#redemption-collection option[value="animata_i"][selected]))
    assert has_element?(view, ~s(#redemption-token-id[value="42"]))

    assert has_element?(view, "#redemption-collection")
    assert has_element?(view, "#redemption-token-id")
  end

  test "OPENSEA_FAILURE_IS_NON_BLOCKING: manual redemption stays usable", %{conn: conn} do
    Application.put_env(:ash_platform, :test_open_sea_handler, fn _ -> {:error, :offline} end)
    view = conn |> signed_in("redeem-open-sea-down") |> activate(@wallet)
    html = render_async(view)
    assert html =~ "Owned NFT lookup is unavailable"
    assert has_element?(view, "#redemption-collection")
    assert has_element?(view, "#redemption-token-id")
  end

  test "WALLET_SWITCH: owned lookup never carries across wallets", %{conn: conn} do
    Application.put_env(:ash_platform, :test_open_sea_handler, fn url ->
      id = if String.contains?(url, String.downcase(@wallet)), do: "42", else: "84"

      nfts =
        if String.contains?(url, "collection=animata&"), do: [%{"identifier" => id}], else: []

      {:ok, %{status: 200, body: %{"nfts" => nfts}}}
    end)

    account = register("redeem-switch", [@wallet, @other])
    view = mount_redeem(conn, account)
    activate(view, @wallet)
    assert render_async(view) =~ "Animata I #42"

    activate(view, @other)
    html = render_async(view)
    assert html =~ "Animata I #84"
    refute html =~ "Animata I #42"
  end

  test "LATE_OPENSEA_RESULT: wallet switch, sign-out, and route leave keep current owned NFTs" do
    stale_name = {:open_sea, @wallet, 3}
    stale_result = {:ok, {:ok, %{animata: [%{label: "Wallet A"}], regents_club: []}}}
    current = %{status: :ready, animata: [%{label: "Current"}], regents_club: []}

    states = [
      %{
        route_spec: %{route_id: :redeem},
        redemption_wallet: @other,
        redemption_generation: 4,
        open_sea_lookup: {:open_sea, @other, 4},
        owned_collectibles: current
      },
      %{
        route_spec: %{route_id: :redeem},
        redemption_wallet: nil,
        redemption_generation: 4,
        open_sea_lookup: nil,
        owned_collectibles: current
      },
      %{
        route_spec: %{route_id: :stake},
        redemption_wallet: nil,
        redemption_generation: 4,
        open_sea_lookup: nil,
        owned_collectibles: current
      }
    ]

    for assigns <- states do
      socket = %Phoenix.LiveView.Socket{assigns: assigns}
      assert {:noreply, returned} = ShellLive.handle_async(stale_name, stale_result, socket)
      assert returned.assigns.owned_collectibles == current
    end
  end

  defp register(suffix, wallets) do
    {:ok, account} =
      Accounts.register_verified("did:privy:#{suffix}", hd(wallets), wallets, actor: %System{})

    account
  end

  defp signed_in(conn, suffix), do: mount_redeem(conn, register(suffix, [@wallet]))

  defp mount_redeem(conn, account) do
    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/redeem")

    view
  end

  defp activate(view, wallet) do
    render_async(view)
    render_hook(view, "redemption_active_wallet", %{"address" => wallet})
    render_async(view)
    view
  end

  defp select(view, collection, token_id) do
    view
    |> form("#redemption-selection", %{"collection" => collection, "token_id" => token_id})
    |> render_change()

    render_async(view)
  end
end
