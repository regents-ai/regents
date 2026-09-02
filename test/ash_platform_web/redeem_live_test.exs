defmodule AshPlatformWeb.RedeemLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.OpenSea.HoldingsCache
  alias AshPlatformWeb.ShellLive

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @third "0x3333333333333333333333333333333333333333"
  @every_control ~w(approve_nft_collection approve_exact_usdc redeem)
  @redeem_42_data "0x1e9a695000000000000000000000000078402119ec6349a0d41f12b54938de7bf783c923000000000000000000000000000000000000000000000000000000000000002a"
  @redeem_43_data "0x1e9a695000000000000000000000000078402119ec6349a0d41f12b54938de7bf783c923000000000000000000000000000000000000000000000000000000000000002b"
  @control_calldata [
    {"approve_nft_collection",
     "0xa22cb46500000000000000000000000071065b775a590c43933f10c0055dc7d74afabb0e0000000000000000000000000000000000000000000000000000000000000001"},
    {"approve_exact_usdc",
     "0x095ea7b300000000000000000000000071065b775a590c43933f10c0055dc7d74afabb0e0000000000000000000000000000000000000000000000000000000004c4b400"},
    {"redeem", @redeem_42_data}
  ]

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
    HoldingsCache.clear()

    on_exit(fn ->
      for key <- [
            :test_open_sea_handler,
            :test_open_sea_current_id,
            :test_open_sea_refresh_gate,
            :test_open_sea_responses,
            :test_open_sea_watcher,
            :test_redemption_nft_approved,
            :test_redemption_nft_owner,
            :test_redemption_owner_unavailable,
            :test_redemption_read_gate,
            :test_redemption_read_result,
            :test_redemption_usdc_allowance,
            :test_redemption_usdc_balance,
            :test_wallet_observation_watcher
          ] do
        Application.delete_env(:ash_platform, key)
      end
    end)

    :ok
  end

  test "PUBLIC_FACTS: anonymous visitors see the exchange and all three collection summaries", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/redeem")
    html = render_async(view)

    assert has_element?(view, "#redemption-page-heading", "Redeem your Animata")

    assert has_element?(
             view,
             ~s(a[href="https://opensea.io/collection/animata"][target="_blank"][rel="noopener noreferrer"]),
             "View collection on OpenSea"
           )

    assert has_element?(
             view,
             ~s(a[href="https://opensea.io/collection/regent-animata-ii"][target="_blank"][rel="noopener noreferrer"]),
             "View collection on OpenSea"
           )

    assert has_element?(
             view,
             ~s(a[href="https://opensea.io/collection/regents-club"][target="_blank"][rel="noopener noreferrer"]),
             "View collection on OpenSea"
           )

    assert has_element?(view, ".redeem-collection-card", "327 held by redeemer")
    assert has_element?(view, ".redeem-collection-card", "284 held by redeemer")
    assert has_element?(view, ".redeem-collection-card", "388 memberships ready")
    assert has_element?(view, ".redeem-collection-card", "1–999")

    assert has_element?(
             view,
             ~s(#redeem-intro-media video[autoplay][muted][loop][playsinline][poster="/images/redeem/animata1and2-poster.jpg"])
           )

    assert has_element?(
             view,
             ~s(img.redeem-intro-poster[src="/images/redeem/animata1and2-poster.jpg"])
           )

    assert html =~ "Redeem your Animata"
    assert html =~ "80 USDC"
    assert html =~ "seven-day REGENT vest"

    assert has_element?(
             view,
             ~s(.redeem-equation[aria-label="One Animata plus 80 USDC becomes five million REGENT vested over seven days and one Regents Club membership"])
           )

    assert html =~
             ~s(<span class="redeem-equation-result"><span class="redeem-pill">5 million REGENT</span><b>+</b><span class="redeem-pill">Regents Club</span></span>)

    assert has_element?(view, ~s(button[data-redeem-connect]), "Connect wallet to redeem")
    refute has_element?(view, "#redemption-selection")

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

  test "ANONYMOUS_ACTIVE_WALLET: any connected wallet can redeem without Regent login", %{
    conn: conn
  } do
    view = mount_redeem(conn)
    render_async(view)
    assert has_element?(view, "button[data-redeem-connect]")

    activate(view, @other)
    assert has_element?(view, "#redemption-selection")
    assert has_element?(view, ~s(.redeem-signer[title="#{@other}"]))

    activate(view, @wallet)
    assert render(view) =~ "Claimable now"
    assert render(view) =~ "1 REGENT"
    assert has_element?(view, ~s(#account-control button[data-account-target="sign-in"]))
  end

  test "CURRENT_NEXT_STEP: only Base's current action is exposed", %{conn: conn} do
    view = conn |> mount_redeem() |> activate(@wallet)
    select(view, "animata_i", "42")
    assert has_element?(view, ".redeem-next-step button", "Redeem Animata")
    refute has_element?(view, ".redeem-next-step button", "Approve NFT")

    Application.put_env(:ash_platform, :test_redemption_nft_approved, false)
    view |> element(~s(button[phx-click="refresh_redemption"])) |> render_click()
    render_async(view)
    assert has_element?(view, ".redeem-next-step button", "Approve NFT collection")

    Application.put_env(:ash_platform, :test_redemption_nft_approved, true)
    Application.put_env(:ash_platform, :test_redemption_usdc_allowance, 0)
    view |> element(~s(button[phx-click="refresh_redemption"])) |> render_click()
    render_async(view)
    assert has_element?(view, ".redeem-next-step button", "Approve 80 USDC")
  end

  test "SELECTION_FAILURE: prior facts remain visible and every step stays sendable", %{
    conn: conn
  } do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, GatedChainClient)

    on_exit(fn ->
      Application.put_env(:ash_platform, :redemption_chain_client, previous_client)
    end)

    view = conn |> mount_redeem() |> activate(@wallet)
    select(view, "animata_i", "42")
    assert has_element?(view, control("redeem"), "Redeem Animata")

    Application.put_env(:ash_platform, :test_redemption_read_result, :error)

    view
    |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => "43"})
    |> render_change()

    render_async(view)

    assert has_element?(view, ".redeem-snapshot-note", "Base block 1,234")
    assert render(view) =~ "Refresh failed"

    for action <- @every_control, do: assert(has_element?(view, control(action)))

    assert has_element?(
             view,
             "#redemption-step-hint",
             "does not yet say which step is needed"
           )

    render_hook(view, "prepare_redemption", %{
      "action" => "redeem",
      "attempt_id" => "newer-selection"
    })

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "newer-selection",
      envelope: %{action: "redeem", data: @redeem_43_data, arguments: %{token_id: 43}}
    })

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

  test "UNCHANGED_SELECTION_NO_READ: edits that leave the selected token unchanged buy no read",
       %{conn: conn} do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, GatedChainClient)

    on_exit(fn ->
      Application.put_env(:ash_platform, :redemption_chain_client, previous_client)
    end)

    view = conn |> mount_redeem() |> activate(@wallet)
    select(view, "animata_i", "42")
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())

    for token_id <- ["42", "042"] do
      view
      |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => token_id})
      |> render_change()
    end

    refute_received {:redemption_read_waiting, _read}
    assert has_element?(view, control("redeem"), "Redeem Animata")

    view
    |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => "43"})
    |> render_change()

    assert_receive {:redemption_read_waiting, read}
    refute_received {:redemption_read_waiting, _second}
    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)
    assert has_element?(view, control("redeem"), "Redeem Animata")
  end

  test "PENDING_READ: while Base is being reread all three steps prepare exact calldata", %{
    conn: conn
  } do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, GatedChainClient)

    on_exit(fn ->
      Application.put_env(:ash_platform, :redemption_chain_client, previous_client)
    end)

    view = conn |> mount_redeem() |> activate(@wallet)
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())

    view
    |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => "42"})
    |> render_change()

    assert_receive {:redemption_read_waiting, read}

    for action <- @every_control, do: assert(has_element?(view, control(action)))

    assert has_element?(view, "#redemption-step-hint", "does not yet say which step is needed")

    for {action, data} <- @control_calldata do
      render_hook(view, "prepare_redemption", %{"action" => action, "attempt_id" => action})

      assert_push_event(view, "redemption:wallet-action", %{
        attempt_id: ^action,
        envelope: %{action: ^action, data: ^data, expected_signer: @wallet}
      })
    end

    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)
    assert has_element?(view, control("redeem"), "Redeem Animata")
  end

  test "SNAPSHOT_NEVER_REFUSES: a predicted shortfall or non-ownership still redeems", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_redemption_nft_owner, @other)
    view = conn |> mount_redeem() |> activate(@wallet)
    select(view, "animata_i", "42")

    assert has_element?(view, control("redeem"), "Redeem Animata")
    assert has_element?(view, "#redemption-step-hint", "does not own the selected Animata")
    refute render(view) =~ "80 USDC required"

    render_hook(view, "prepare_redemption", %{"action" => "redeem", "attempt_id" => "not-owned"})

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "not-owned",
      envelope: %{action: "redeem", data: @redeem_42_data}
    })

    Application.delete_env(:ash_platform, :test_redemption_nft_owner)
    Application.put_env(:ash_platform, :test_redemption_usdc_balance, 1)
    view |> element("#redemption-refresh") |> render_click()
    render_async(view)

    assert has_element?(view, control("redeem"), "Redeem Animata")
    assert has_element?(view, "#redemption-step-hint", "holds less than 80 USDC")

    render_hook(view, "prepare_redemption", %{"action" => "redeem", "attempt_id" => "short-usdc"})

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "short-usdc",
      envelope: %{action: "redeem", data: @redeem_42_data}
    })
  end

  test "NO_TOKEN_NO_CALLDATA: controls appear only once a token is selected", %{conn: conn} do
    view = conn |> mount_redeem() |> activate(@wallet)

    refute has_element?(view, ".redeem-next-step button")
    assert has_element?(view, ".redeem-next-step h3", "Select an Animata")
    assert has_element?(view, ~s|button[data-redemption-action="claim"]:not([disabled])|)

    select(view, "animata_i", "42")
    assert has_element?(view, control("redeem"), "Redeem Animata")

    select(view, "animata_i", "")
    refute has_element?(view, ".redeem-next-step button")
    assert has_element?(view, "#redemption-step-hint", "Choose an eligible Animata")
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
    view = conn |> mount_redeem() |> activate(@wallet)
    select(view, "animata_i", "42")

    assert has_element?(
             view,
             ".redeem-summary .redeem-metric:first-child",
             "80.00 USDC"
           )

    assert has_element?(view, ".redeem-snapshot-note", "Base block 1,234")
    assert has_element?(view, ".redeem-contract-details dt", ~r/\ABase block\z/)

    assert has_element?(
             view,
             ~s(#redemption-refresh-status[data-visible="false"][aria-hidden="true"])
           )

    refute render(view) =~ "Refresh complete. Data is current"

    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    view |> element("#redemption-refresh") |> render_click()
    assert_receive {:redemption_read_waiting, read}

    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "80.00 USDC")

    assert has_element?(view, ".redeem-snapshot-note", "Base block 1,234")

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
             "Refresh complete. Data is current at Base block 1,234."
           )

    Application.put_env(:ash_platform, :test_redemption_usdc_balance, 125_000_000)
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    view |> element("#redemption-refresh") |> render_click()
    assert_receive {:redemption_read_waiting, read}

    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "80.00 USDC")
    refute has_element?(view, ".redeem-summary .redeem-metric:first-child", "125.00 USDC")
    assert has_element?(view, ".redeem-summary")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    refute render(view) =~ "Refresh complete. Data is current"
    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)

    assert has_element?(
             view,
             ".redeem-summary .redeem-metric:first-child",
             "125.00 USDC"
           )

    assert has_element?(view, ".redeem-snapshot-note", "Base block 1,234")

    Application.put_env(:ash_platform, :test_redemption_read_result, :error)
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    view |> element("#redemption-refresh") |> render_click()
    assert_receive {:redemption_read_waiting, read}
    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "125.00 USDC")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    refute render(view) =~ "Refresh complete. Data is current"
    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)

    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "125.00 USDC")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    assert render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."

    Application.put_env(:ash_platform, :test_redemption_read_result, :ok)
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())
    view |> element("#redemption-refresh") |> render_click()
    assert_receive {:redemption_read_waiting, read}
    refute render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."
    assert has_element?(view, ".redeem-summary .redeem-metric:first-child", "125.00 USDC")
    assert has_element?(view, ~s(#redemption-refresh-status[data-visible="false"]))
    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(read, :continue_redemption_read)
    render_async(view)

    refute render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."

    assert has_element?(
             view,
             ~s(#redemption-refresh-status[data-visible="true"]),
             "Refresh complete. Data is current at Base block 1,234."
           )
  end

  test "DIRECT_REDEEM: each eligible click pushes one fresh envelope with no lifecycle UI", %{
    conn: conn
  } do
    view = conn |> mount_redeem() |> activate(@wallet)
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
    assert first.data == @redeem_42_data

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
    view = conn |> mount_redeem() |> activate(@wallet)
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

    view = conn |> mount_redeem() |> activate(@wallet)
    render_async(view)
    assert has_element?(view, ~s(.redeem-owned-list button[phx-value-token-id="42"]))

    assert has_element?(
             view,
             ~s(.redeem-owned-list a[target="_blank"][rel="noopener noreferrer"]),
             "Regents Club"
           )

    view |> element(~s(.redeem-owned-list button[phx-value-token-id="42"])) |> render_click()
    render_async(view)
    assert has_element?(view, ~s(#redemption-collection option[value="animata_i"][selected]))
    assert has_element?(view, ~s(#redemption-token-id[value="42"]))

    assert has_element?(view, "#redemption-collection")
    assert has_element?(view, "#redemption-token-id")
  end

  test "OPENSEA_FAILURE_IS_NON_BLOCKING: manual redemption stays usable", %{conn: conn} do
    Application.put_env(:ash_platform, :test_open_sea_handler, fn _ -> {:error, :offline} end)
    view = conn |> mount_redeem() |> activate(@wallet)
    html = render_async(view)
    assert html =~ "Owned NFT lookup is unavailable"
    assert has_element?(view, "#redemption-collection")
    assert has_element?(view, "#redemption-token-id")
  end

  test "OPENSEA_REFRESH_FAILURE: previously loaded cards remain available" do
    name = {:open_sea, @wallet}

    current = %{
      status: :refreshing,
      animata: [%{collection: "animata_i", token_id: "42"}],
      regents_club: []
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, open_sea_lookup: name, owned_collectibles: current}
    }

    assert {:noreply, returned} =
             ShellLive.handle_async(name, {:ok, {:error, :unavailable}}, socket)

    assert returned.assigns.owned_collectibles == %{current | status: :unavailable}
  end

  test "CHAIN_REFRESH_FAILURE: a retained collection stops refreshing without losing cards" do
    name = {:redemption, 4}

    current = %{
      status: :refreshing,
      animata: [%{collection: "animata_i", token_id: "42"}],
      regents_club: []
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        route_spec: %{route_id: :redeem},
        redemption_generation: 4,
        redemption_read: %{name: name, announce_refresh: true},
        redemption: %{block_number: 1_234},
        redemption_snapshot_selection: nil,
        redemption_status: :ready,
        redemption_notice: nil,
        owned_collectibles: current
      }
    }

    assert {:noreply, returned} =
             ShellLive.handle_async(name, {:ok, {4, {:error, :unavailable}}}, socket)

    assert returned.assigns.owned_collectibles == %{current | status: :unavailable}
    assert returned.assigns.redemption == %{block_number: 1_234}
    assert returned.assigns.redemption_status == :ready
  end

  test "FIRST_WALLET_READ_FAILURE: public collection data stays visible with recovery controls",
       %{
         conn: conn
       } do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)

    on_exit(fn ->
      Application.put_env(:ash_platform, :redemption_chain_client, previous_client)
    end)

    view = mount_redeem(conn)
    render_async(view)
    Application.put_env(:ash_platform, :redemption_chain_client, GatedChainClient)
    Application.put_env(:ash_platform, :test_redemption_read_result, :error)

    render_hook(view, "redemption_active_wallet", %{"address" => @wallet})
    render_async(view)

    assert has_element?(view, ".redeem-collections", "Three connected collections")
    assert has_element?(view, ".redeem-wallet-recovery", "Try again")
    refute has_element?(view, ".redeem-wallet-loading")
  end

  test "BOUNDED_GALLERY: large collections reveal animated cards in small batches", %{conn: conn} do
    Application.put_env(:ash_platform, :test_open_sea_handler, fn url ->
      nfts =
        if String.contains?(url, "collection=animata&"),
          do: for(id <- 1..30, do: %{"identifier" => Integer.to_string(id)}),
          else: []

      {:ok, %{status: 200, body: %{"nfts" => nfts}}}
    end)

    view = conn |> mount_redeem() |> activate(@wallet)
    render_async(view)

    assert has_element?(view, ~s(.redeem-nft-card[phx-value-token-id="24"]))
    refute has_element?(view, ~s(.redeem-nft-card[phx-value-token-id="25"]))
    assert has_element?(view, ".redeem-owned-more", "Show more (6 remaining)")

    view |> element(".redeem-owned-more") |> render_click()

    assert has_element?(view, ~s(.redeem-nft-card[phx-value-token-id="30"]))
    refute has_element?(view, ".redeem-owned-more")
  end

  test "CONFIRMED_REDEMPTION_REFRESH: owned cards stay visible until a fresh lookup replaces them",
       %{
         conn: conn
       } do
    Application.put_env(:ash_platform, :test_open_sea_current_id, "42")

    Application.put_env(:ash_platform, :test_open_sea_handler, fn url ->
      id = Application.get_env(:ash_platform, :test_open_sea_current_id, "42")

      if id == "43" and String.contains?(url, "collection=animata&") do
        case Application.get_env(:ash_platform, :test_open_sea_refresh_gate) do
          test_pid when is_pid(test_pid) ->
            send(test_pid, {:open_sea_refresh_waiting, self()})

            receive do
              :continue_open_sea_refresh -> :ok
            after
              5_000 -> raise "timed out waiting to continue the OpenSea refresh"
            end

          _ ->
            :ok
        end
      end

      nfts =
        if String.contains?(url, "collection=animata&"), do: [%{"identifier" => id}], else: []

      {:ok, %{status: 200, body: %{"nfts" => nfts}}}
    end)

    view = conn |> mount_redeem() |> activate(@wallet)
    render_async(view)
    assert has_element?(view, ~s(.redeem-nft-card[phx-value-token-id="42"]))

    Application.put_env(:ash_platform, :test_open_sea_current_id, "43")
    Application.put_env(:ash_platform, :test_open_sea_refresh_gate, self())
    render_hook(view, "refresh_redemption", %{"refresh_owned" => true})
    assert_receive {:open_sea_refresh_waiting, lookup}

    assert has_element?(view, ~s(.redeem-nft-card[phx-value-token-id="42"]))
    assert has_element?(view, ".redeem-owned-status", "Updating your collection")

    Application.delete_env(:ash_platform, :test_open_sea_refresh_gate)
    send(lookup, :continue_open_sea_refresh)
    render_async(view)
    assert has_element?(view, ~s(.redeem-nft-card[phx-value-token-id="43"]))
    refute has_element?(view, ~s(.redeem-nft-card[phx-value-token-id="42"]))
  end

  test "LOOPING_REFRESH: repeated post-redemption refreshes buy one extra provider read", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())
    view = conn |> mount_redeem() |> activate(@wallet)
    render_async(view)
    assert length(drain_requests()) == 3

    for _ <- 1..3 do
      render_hook(view, "refresh_redemption", %{"refresh_owned" => true})
      render_async(view)
    end

    assert length(drain_requests()) == 3
    assert has_element?(view, "#redemption-token-id")
  end

  test "TYPING_KEEPS_ITS_SHARE: token ID edits during an outage never spend a lookup", %{
    conn: conn
  } do
    hold_lookup_share(2)

    Application.put_env(:ash_platform, :test_open_sea_handler, fn url ->
      if String.contains?(url, String.downcase(@wallet)),
        do: {:ok, %{status: 502, body: %{}}},
        else: {:ok, %{status: 200, body: %{"nfts" => [%{"identifier" => "84"}]}}}
    end)

    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    view = conn |> mount_redeem() |> activate(@wallet)
    assert has_element?(view, ".redeem-owned-status", "Owned NFT lookup is unavailable")
    assert length(drain_requests()) == 3

    for token_id <- ["4", "42", "421"], do: select(view, "animata_i", token_id)

    assert drain_requests() == []
    assert has_element?(view, ".redeem-owned-status", "Owned NFT lookup is unavailable")

    activate(view, @other)
    assert length(drain_requests()) == 3
    assert has_element?(view, ~s(.redeem-nft-card[phx-value-token-id="84"]))
  end

  test "LOOKUP_BUDGET: a connection past its share falls back to manual entry", %{conn: conn} do
    hold_lookup_share(2)
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    view = conn |> mount_redeem() |> activate(@wallet)
    activate(view, @other)
    assert length(drain_requests()) == 6

    activate(view, @third)
    assert drain_requests() == []
    assert has_element?(view, ".redeem-owned-status", "Owned NFT lookup is unavailable")
    assert has_element?(view, "#redemption-collection")
    assert has_element?(view, "#redemption-token-id")
    refute has_element?(view, ~s(.redeem-notice[role="alert"]))

    render_hook(view, "prepare_redemption", %{"action" => "claim", "attempt_id" => "still-open"})
    assert_push_event(view, "redemption:wallet-action", %{attempt_id: "still-open"})
  end

  test "SERVER_LOOKUP_CEILING: a server past its minute of lookups still redeems", %{conn: conn} do
    hold_server_minute(0)
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    view = conn |> mount_redeem() |> activate(@wallet)

    assert drain_requests() == []
    assert has_element?(view, ".redeem-owned-status", "Owned NFT lookup is unavailable")
    assert has_element?(view, "#redemption-collection")
    assert has_element?(view, "#redemption-token-id")
    refute has_element?(view, ~s(.redeem-notice[role="alert"]))

    render_hook(view, "prepare_redemption", %{"action" => "claim", "attempt_id" => "still-open"})
    assert_push_event(view, "redemption:wallet-action", %{attempt_id: "still-open"})
  end

  test "WALLET_SWITCH: owned lookup never carries across wallets", %{conn: conn} do
    Application.put_env(:ash_platform, :test_open_sea_handler, fn url ->
      id = if String.contains?(url, String.downcase(@wallet)), do: "42", else: "84"

      nfts =
        if String.contains?(url, "collection=animata&"), do: [%{"identifier" => id}], else: []

      {:ok, %{status: 200, body: %{"nfts" => nfts}}}
    end)

    view = mount_redeem(conn)
    activate(view, @wallet)
    render_async(view)
    assert has_element?(view, ~s(.redeem-owned-list button[phx-value-token-id="42"]))

    activate(view, @other)
    render_async(view)
    assert has_element?(view, ~s(.redeem-owned-list button[phx-value-token-id="84"]))
    refute has_element?(view, ~s(.redeem-owned-list button[phx-value-token-id="42"]))
  end

  test "LATE_OPENSEA_RESULT: wallet switch, sign-out, and route leave keep current owned NFTs" do
    stale_name = {:open_sea, @wallet}
    stale_result = {:ok, {:ok, %{animata: [%{label: "Wallet A"}], regents_club: []}}}
    current = %{status: :ready, animata: [%{label: "Current"}], regents_club: []}

    states = [
      %{
        route_spec: %{route_id: :redeem},
        redemption_wallet: @other,
        redemption_generation: 4,
        open_sea_lookup: {:open_sea, @other},
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

  test "OBSERVATION_IS_CAPPED: Redeem reports one outcome and caps live observations", %{
    conn: conn
  } do
    view = mount_redeem(conn)
    render_async(view)
    Application.put_env(:ash_platform, :test_wallet_observation_watcher, self())

    observers =
      for index <- 1..8 do
        render_hook(view, "observe_redemption_transaction", observation("obs-#{index}"))
        assert_receive {:wallet_observation, :redemption, _transaction, observer}
        observer
      end

    render_hook(view, "observe_redemption_transaction", observation("obs-9"))
    refute_receive {:wallet_observation, _scope, _transaction, _observer}, 200

    assert_push_event(view, "redemption:transaction-result", %{
      observation_id: "obs-9",
      result: :unavailable
    })

    [first | held] = observers
    send(first, {:wallet_observation_result, :reverted})

    assert_push_event(view, "redemption:transaction-result", %{
      observation_id: "obs-1",
      result: :reverted
    })

    for observer <- held, do: send(observer, {:wallet_observation_result, :success})
    render_async(view)
  end

  defp control(action),
    do: ~s|.redeem-next-step button[data-redemption-action="#{action}"]:not([disabled])|

  defp observation(id),
    do: %{
      "observation_id" => id,
      "hash" => "0x" <> String.duplicate("a", 64),
      "signer" => @wallet,
      "to" => "0x3333333333333333333333333333333333333333",
      "data" => "0xa9059cbb"
    }

  defp hold_lookup_share(share) do
    previous = Application.get_env(:ash_platform, :opensea_lookups_per_minute)
    Application.put_env(:ash_platform, :opensea_lookups_per_minute, share)
    on_exit(fn -> Application.put_env(:ash_platform, :opensea_lookups_per_minute, previous) end)
  end

  defp hold_server_minute(lookups) do
    previous = Application.get_env(:ash_platform, :opensea_live_lookups_per_minute)
    Application.put_env(:ash_platform, :opensea_live_lookups_per_minute, lookups)

    on_exit(fn ->
      Application.put_env(:ash_platform, :opensea_live_lookups_per_minute, previous)
    end)
  end

  defp drain_requests(acc \\ []) do
    receive do
      {:open_sea_request, url, _options, _pid} -> drain_requests([url | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  # The wallet arrives while the public read is still open, so that read is
  # cancelled and replaced. A cancelled read reported nothing about Base and
  # must not be mistaken for a failed one.
  test "WALLET_DURING_FIRST_READ: replacing the open public read never reports Base unavailable",
       %{conn: conn} do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, GatedChainClient)

    on_exit(fn ->
      Application.put_env(:ash_platform, :redemption_chain_client, previous_client)
    end)

    Application.put_env(:ash_platform, :test_redemption_read_gate, self())

    view = mount_redeem(conn)
    assert_receive {:redemption_read_waiting, public_read}
    public_read_ref = Process.monitor(public_read)

    render_hook(view, "redemption_active_wallet", %{"address" => @wallet})

    assert_receive {:redemption_read_waiting, wallet_read}
    assert_receive {:DOWN, ^public_read_ref, :process, ^public_read, _reason}

    refute render(view) =~ "Redemption details are unavailable right now."
    assert redemption_assigns(view).redemption_status == :loading

    Application.delete_env(:ash_platform, :test_redemption_read_gate)
    send(wallet_read, :continue_redemption_read)
    render_async(view)

    assigns = redemption_assigns(view)
    assert assigns.redemption_status == :ready
    assert assigns.redemption_wallet == @wallet
    assert has_element?(view, "#redemption-collections")
  end

  # A first read that genuinely failed still says the page is unavailable.
  test "FIRST_READ_FAILURE: a failed first read reports Base unavailable", %{conn: conn} do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, GatedChainClient)
    Application.put_env(:ash_platform, :test_redemption_read_result, :error)

    on_exit(fn ->
      Application.put_env(:ash_platform, :redemption_chain_client, previous_client)
    end)

    view = mount_redeem(conn)
    render_async(view)

    assert redemption_assigns(view).redemption_status == :error

    assert has_element?(
             view,
             ~s(p[role="alert"]),
             "Redemption details are unavailable right now."
           )
  end

  defp mount_redeem(conn) do
    {:ok, view, _html} = live(conn, "/redeem")

    view
  end

  defp redemption_assigns(view), do: :sys.get_state(view.pid).socket.assigns

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
