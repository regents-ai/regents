defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Staking}
  alias AshPlatform.Actors.{Human, System}

  @wallet "0x1111111111111111111111111111111111111111"
  @tx_hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)

  setup do
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)

    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_staking_approval_status)
      Application.delete_env(:ash_platform, :test_staking_confirmation_result)
      restore_env(:wallet_action_clock, previous_clock)
    end)

    :ok
  end

  test "anonymous visitors can see public staking truth but cannot prepare actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stake")
    html = render_async(view)

    assert html =~ "100 REGENT"
    assert html =~ "Connect your account"
    refute has_element?(view, "#regent-staking [phx-click=prepare_staking]")
  end

  test "a signed-in wallet reviews, explicitly signs, confirms and refreshes", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-live", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    assert has_element?(view, "#staking-amount")
    assert render(view) =~ "5 REGENT"

    view
    |> form("#staking-amount-form", %{"amount" => "1"})
    |> render_change()

    view
    |> element(~s(button[phx-value-action="stake"]), "Review stake")
    |> render_click()

    assert has_element?(view, ".stake-review", "Stake REGENT")
    assert render(view) =~ "separate exact token approval"
    assert render(view) =~ "1 REGENT"
    assert render(view) =~ "0x1111…1111"
    action_id = prepared_action_id(render(view))

    view
    |> element(".stake-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "staking:prepared", %{
      envelope: %{action: "stake", expected_signer: @wallet},
      approval_transaction_hash: nil
    })

    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "approval",
      "transaction_hash" => @approval_hash
    })

    html = render_async(view)
    assert html =~ "REGENT approval confirmed"
    assert html =~ "Continue after approval"

    view
    |> element(".stake-submission button", "Continue after approval")
    |> render_click()

    assert_push_event(view, "staking:prepared", %{
      envelope: %{action: "stake", expected_signer: @wallet},
      approval_transaction_hash: @approval_hash
    })

    render_hook(view, "sign_prepared_staking", %{"action-id" => action_id})

    refute_push_event(view, "staking:prepared", _)

    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "action",
      "transaction_hash" => @tx_hash
    })

    render_hook(view, "confirm_staking", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    html = render_async(view)
    assert html =~ "Confirmed on Base"
    assert html =~ "5 REGENT"
    refute html =~ "Review before signing"
  end

  test "a server-verified reverted main action resets the flow for a fresh prepare", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_confirmation_result, :reverted)

    {:ok, account} =
      Accounts.register_verified("did:privy:stake-reverted", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    action_id = prepared_action_id(render(view))

    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "action",
      "transaction_hash" => @tx_hash
    })

    render_hook(view, "confirm_staking", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    html = render_async(view)
    assert html =~ "staking transaction reverted"
    refute html =~ "Submitted transaction"
    assert has_element?(view, ~s(button[phx-value-action="stake"]), "Review stake")
    assert_push_event(view, "staking:action-reverted", %{})
  end

  test "a verified approval can be abandoned without sending main and a fresh action can be prepared",
       %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-abandon", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    action_id = prepared_action_id(render(view))

    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "approval",
      "transaction_hash" => @approval_hash
    })

    render_async(view)
    assert render(view) =~ "Continue after approval"
    refute render(view) =~ "Staking transaction:"

    view |> element(~s(button[phx-click="abandon_staking_approval"])) |> render_click()

    html = render(view)
    assert html =~ "exact REGENT allowance remains onchain"
    refute html =~ "Submitted transaction"
    assert_push_event(view, "staking:abandoned", %{})

    send(view.pid, {:staking_envelope_expired, action_id})
    refute render(view) =~ "approval review expired"

    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    assert render(view) =~ "Review before signing"
  end

  test "a pending approval can be abandoned while preserving its uncertain hash", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_approval_status, :pending)

    {:ok, account} =
      Accounts.register_verified("did:privy:stake-pending-abandon", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    action_id = prepared_action_id(render(view))

    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "approval",
      "transaction_hash" => @approval_hash
    })

    render_async(view)
    view |> element(~s(button[phx-click="abandon_staking_approval"])) |> render_click()

    html = render(view)
    assert html =~ "0xcdcdcd…cdcd"
    assert html =~ "may still confirm later"
    assert html =~ "before relying on the allowance state"
    refute html =~ "exact REGENT allowance remains onchain"
    refute html =~ "Submitted transaction"
    assert_push_event(view, "staking:abandoned", %{})
  end

  test "an expired restored approval-only action clears without sending main", %{conn: conn} do
    expired_at = DateTime.utc_now() |> DateTime.add(-11, :minute)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> expired_at end)

    {:ok, account} =
      Accounts.register_verified("did:privy:stake-expired", @wallet, [@wallet], actor: %System{})

    actor = %Human{human_account_id: account.id}
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1", actor: actor)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> DateTime.utc_now() end)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)

    render_hook(view, "restore_staking_submission", %{
      "envelope" => envelope,
      "approval_transaction_hash" => @approval_hash
    })

    html = render(view)
    assert html =~ "approval review expired"
    assert html =~ "0xcdcdcd…cdcd"
    assert html =~ "may still confirm later"
    assert html =~ "before relying on the allowance state"
    refute html =~ "exact REGENT allowance remains onchain"
    refute html =~ "Submitted transaction"
    assert_push_event(view, "staking:abandoned", %{})

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    assert render(view) =~ "Review before signing"
  end

  test "an approval cannot be abandoned after the main transaction hash exists", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-no-abandon", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    action_id = prepared_action_id(render(view))

    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "action",
      "transaction_hash" => @tx_hash
    })

    render_hook(view, "abandon_staking_approval", %{})

    assert render(view) =~ "Staking transaction:"
    refute_push_event(view, "staking:abandoned", _)
  end

  test "unknown or mismatched confirmations fail closed", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-mismatch", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)

    render_hook(view, "confirm_staking", %{"action_id" => "other", "transaction_hash" => @tx_hash})

    assert render(view) =~ "does not match the reviewed action"
  end

  test "a late confirmation from a departed route is ignored" do
    route_spec = AshPlatformWeb.RouteCatalog.fetch!(:techtree, %{})

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        route_spec: route_spec,
        staking_confirmation_name: nil,
        staking_notice: nil,
        staking_signing?: false
      }
    }

    assert {:noreply, unchanged} =
             AshPlatformWeb.ShellLive.handle_async(
               {:staking_confirmation, "old"},
               {:ok, {:ok, %{staking: %{wallet_stake_balance: "999"}}}},
               socket
             )

    assert unchanged.assigns.staking_notice == nil
    refute Map.has_key?(unchanged.assigns, :staking)
  end

  defp prepared_action_id(html) do
    [id] = Regex.run(~r/phx-value-action-id="([a-f0-9]+)"/, html, capture: :all_but_first)
    id
  end

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
