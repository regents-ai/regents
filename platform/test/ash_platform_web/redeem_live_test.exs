defmodule AshPlatformWeb.RedeemLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.OpenSea.HoldingsCache
  alias AshPlatformWeb.ShellLive

  # Invariants covered:
  # - smoke: 200 mount and the redeem heading landmark
  # - redeem eligibility and pass counts on the public collection cards
  # - signed-out vs signed-in gating of send controls
  # - prepare_redemption wallet handoff payloads, including during a pending read
  # - allowance/approval branch (NFT collection, exact USDC, then redeem)
  # - an unavailable figure or failed first read does not hide a usable page (gu2.18)
  # - refresh/lookup refusal keeps the last reading and still prepares a send
  # - on-chain-button: a predicted shortfall or pending read never blocks a press

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @reconnect_request "Please reconnect to the active wallet '0x1111…1111' to interact onchain."
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
    assert conn |> get("/redeem") |> html_response(200)
    {:ok, view, _html} = live(conn, "/redeem")
    render_async(view)

    assert has_element?(view, "#redemption-page-heading")
    assert has_element?(view, ".redeem-collection-card dd", "327")
    assert has_element?(view, ".redeem-collection-card dd", "284")
    assert has_element?(view, ".redeem-collection-card dd", "1,610 / 1,998")
    assert has_element?(view, ~s|button[data-account-target="sign-in"]|)
    refute has_element?(view, "#redemption-selection")
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
    assert has_element?(view, ~s|button[data-account-target="sign-in"]|)

    activate(view, @other)
    assert has_element?(view, "#redemption-selection")

    activate(view, @wallet)
    assert render(view) =~ "Claimable now"
    assert has_element?(view, ~s(#account-control button[data-account-target="sign-in"]))
  end

  test "SIGN_IN_BEFORE_SENDING: a wallet with no sign-in reads its position and sends nothing", %{
    conn: conn
  } do
    view = conn |> mount_redeem() |> activate(@wallet)
    select(view, "animata_i", "42")

    assert render(view) =~ "Claimable now"
    assert has_element?(view, "#redemption-selection")

    assert_offers_sign_in(view)
    refute_push_event(view, "redemption:wallet-action", _)
  end

  test "WALLET_MISMATCH: a sign-in on one wallet cannot send from another", %{conn: conn} do
    view = redeem_as_signer(conn, "wallet-mismatch")
    select(view, "animata_i", "42")

    render_hook(view, "prepare_redemption", %{"action" => "redeem", "attempt_id" => "matching"})
    assert_push_event(view, "redemption:wallet-action", %{attempt_id: "matching"})

    activate(view, @other)
    select(view, "animata_i", "42")

    assert_refuses_every_action(view, @reconnect_request)

    refute_push_event(view, "redemption:wallet-action", _)
    render_hook(view, "dismiss_wallet_reconnect", %{})
    refute has_element?(view, "#wallet-reconnect-dialog")

    render_hook(view, "prepare_redemption", %{"action" => "redeem", "attempt_id" => "again"})
    assert has_element?(view, "#wallet-reconnect-dialog", @reconnect_request)

    activate(view, @wallet)
    refute has_element?(view, "#wallet-reconnect-dialog")
    select(view, "animata_i", "42")
    render_hook(view, "prepare_redemption", %{"action" => "redeem", "attempt_id" => "restored"})
    assert_push_event(view, "redemption:wallet-action", %{attempt_id: "restored"})
  end

  test "DISCONNECTED_WALLET: releasing every wallet clears the position and offers the connection again",
       %{conn: conn} do
    view = conn |> mount_redeem() |> activate(@wallet)

    assert redemption_assigns(view).redemption_wallet == @wallet
    assert has_element?(view, "#redemption-selection")

    activate(view, nil)

    assigns = redemption_assigns(view)
    assert assigns.redemption_wallet == nil
    assert assigns.redemption.wallet_address == nil
    assert assigns.redemption.usdc_balance == nil
    assert assigns.redemption.nft_owner == nil
    assert assigns.owned_collectibles == %{status: :idle, animata: [], regents_club: []}

    assert has_element?(view, ~s|button[data-account-target="sign-in"]|)
    refute has_element?(view, "#redemption-selection")
    refute render(view) =~ "Claimable now"
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

    view = redeem_as_signer(conn, "selection-failure")
    select(view, "animata_i", "42")
    assert has_element?(view, control("redeem"), "Redeem Animata")

    Application.put_env(:ash_platform, :test_redemption_read_result, :error)

    view
    |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => "43"})
    |> render_change()

    render_async(view)

    assert has_element?(view, ".redeem-snapshot-note", "Base block 1,234")

    for action <- @every_control, do: assert(has_element?(view, control(action)))

    render_hook(view, "prepare_redemption", %{
      "action" => "redeem",
      "attempt_id" => "newer-selection"
    })

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "newer-selection",
      envelope: %{action: "redeem", data: @redeem_43_data, arguments: %{token_id: 43}}
    })

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

    view = redeem_as_signer(conn, "unchanged-selection")
    select(view, "animata_i", "42")
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())

    for token_id <- ["42", "042"] do
      view
      |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => token_id})
      |> render_change()
    end

    refute_received {:redemption_read_waiting, _read}

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

    view = redeem_as_signer(conn, "pending-read")
    Application.put_env(:ash_platform, :test_redemption_read_gate, self())

    view
    |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => "42"})
    |> render_change()

    assert_receive {:redemption_read_waiting, read}

    for action <- @every_control, do: assert(has_element?(view, control(action)))

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
    view = redeem_as_signer(conn, "snapshot-never-refuses")
    select(view, "animata_i", "42")

    assert has_element?(view, control("redeem"), "Redeem Animata")

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

    render_hook(view, "prepare_redemption", %{"action" => "redeem", "attempt_id" => "short-usdc"})

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "short-usdc",
      envelope: %{action: "redeem", data: @redeem_42_data}
    })
  end

  test "NO_TOKEN_NO_CALLDATA: controls appear only once a token is selected", %{conn: conn} do
    view = redeem_as_signer(conn, "no-token-no-calldata")

    refute has_element?(view, ".redeem-next-step button")
    assert has_element?(view, ~s|button[data-redemption-action="claim"]:not([disabled])|)

    select(view, "animata_i", "42")
    assert has_element?(view, control("redeem"), "Redeem Animata")

    select(view, "animata_i", "")
    refute has_element?(view, ".redeem-next-step button")
  end

  test "DIRECT_REDEEM: each eligible click pushes one fresh envelope with no lifecycle UI", %{
    conn: conn
  } do
    view = redeem_as_signer(conn, "direct-redeem")
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
  end

  test "CLAIM_DIRECTLY: unlocked REGENT is its own exact control", %{conn: conn} do
    view = redeem_as_signer(conn, "claim-directly")
    assert has_element?(view, ~s|button[data-redemption-action="claim"]:not([disabled])|)

    render_hook(view, "prepare_redemption", %{
      "action" => "claim",
      "attempt_id" => "claim-attempt"
    })

    assert_push_event(view, "redemption:wallet-action", %{
      attempt_id: "claim-attempt",
      envelope: %{action: "claim", expected_signer: @wallet}
    })
  end

  test "OPENSEA_FAILURE_IS_NON_BLOCKING: manual redemption stays usable", %{conn: conn} do
    Application.put_env(:ash_platform, :test_open_sea_handler, fn _ -> {:error, :offline} end)
    view = conn |> mount_redeem() |> activate(@wallet)
    html = render_async(view)
    assert html =~ "Owned NFT lookup is unavailable"
    assert has_element?(view, "#redemption-collection")
    assert has_element?(view, "#redemption-token-id")
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

    assert has_element?(view, "#redemption-collections")
    assert has_element?(view, ".redeem-wallet-recovery", "Try again")
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

    view = conn |> signed_in_redeem("lookup-budget", @third) |> activate(@wallet)
    activate(view, @other)
    assert length(drain_requests()) == 6

    activate(view, @third)
    assert drain_requests() == []
    assert has_element?(view, "#redemption-collection")
    assert has_element?(view, "#redemption-token-id")

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

  defp drain_requests(acc \\ []) do
    receive do
      {:open_sea_request, url, _options, _pid} -> drain_requests([url | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp assert_refuses_every_action(view, request) do
    for action <- ["claim" | @every_control] do
      render_hook(view, "dismiss_wallet_reconnect", %{})
      render_hook(view, "prepare_redemption", %{"action" => action, "attempt_id" => action})

      assert_push_event(view, "redemption:wallet-refusal", %{
        attempt_id: ^action,
        sign_in: false
      })

      refute has_element?(view, ".redeem-notice")
      assert has_element?(view, "#wallet-reconnect-dialog", request)
    end
  end

  defp assert_offers_sign_in(view) do
    refute has_element?(view, "button[data-redemption-action]")

    assert has_element?(
             view,
             ~s|.redeem-next-step button[data-account-target="sign-in"]|,
             "Redeem Animata"
           )

    assert has_element?(
             view,
             ~s|button.redeem-claim[data-account-target="sign-in"]|,
             "Claim unlocked REGENT"
           )

    for action <- ["claim" | @every_control] do
      render_hook(view, "prepare_redemption", %{"action" => action, "attempt_id" => action})
      assert_push_event(view, "redemption:wallet-refusal", %{attempt_id: ^action, sign_in: true})
    end

    refute has_element?(view, ~s(.redeem-notice[role="alert"]))
  end

  defp signed_in_redeem(conn, suffix, wallet) do
    assert {:ok, account} =
             Accounts.register_verified("did:privy:#{suffix}", wallet, [wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/redeem")

    view
  end

  defp redeem_as_signer(conn, suffix),
    do: conn |> signed_in_redeem(suffix, @wallet) |> activate(@wallet)

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
