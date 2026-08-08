defmodule AshPlatformWeb.AutolaunchSubjectPaymentLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"
  @token "0x2222222222222222222222222222222222222222"
  @splitter "0x3333333333333333333333333333333333333333"
  @ingress "0x4444444444444444444444444444444444444444"
  @treasury "0x5555555555555555555555555555555555555555"
  @factory "0x6666666666666666666666666666666666666666"
  @subject_id "0x" <> String.duplicate("53", 32)
  @transaction_hash "0x" <> String.duplicate("ab", 32)

  @removed_events [
    {"prepare_autolaunch_subject_payment",
     %{
       "subject_payment" => %{"label" => "Sponsor", "canonical" => "false"}
     }},
    {"sign_prepared_autolaunch_subject_payment", %{"action-id" => "subject-action"}},
    {"autolaunch_subject_payment_submitted",
     %{
       "action_id" => "subject-action",
       "phase" => "action",
       "transaction_hash" => @transaction_hash
     }},
    {"restore_autolaunch_subject_payment_submission",
     %{"envelope" => %{}, "transaction_hash" => @transaction_hash}},
    {"retry_autolaunch_subject_payment_approval_verification", %{}},
    {"confirm_autolaunch_subject_payment",
     %{"action_id" => "subject-action", "transaction_hash" => @transaction_hash}},
    {"retry_autolaunch_subject_payment_confirmation", %{}},
    {"cancel_autolaunch_subject_payment_review", %{}},
    {"autolaunch_subject_payment_wallet_failed", %{"message" => "cancelled"}}
  ]

  setup do
    account =
      Accounts.register_verified!(
        "did:privy:autolaunch-subject-payment-live",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    subject =
      Autolaunch.import_subject!(
        @subject_id,
        "agent",
        8453,
        @token,
        @splitter,
        @ingress,
        @treasury,
        @factory,
        @wallet,
        1500,
        250,
        200,
        "0",
        "0",
        "0",
        actor: %System{}
      )

    %{account: account, subject: subject}
  end

  test "subject page remains read-only with no owner payment controls or hook", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, html} = subject_live(conn, account, subject)

    for selector <- [
          "#subject-payment-wallet",
          "#subject-payment-link-create-form",
          "#subject-payment-link-canonical-form",
          "#subject-payment-link-state-form",
          "#subject-ingress-sweep-form",
          "#subject-stake-form",
          "#subject-unstake-form",
          "#subject-claim-usdc-form",
          "#subject-payment-review"
        ] do
      refute has_element?(view, selector)
    end

    for copy <- [
          "Payment links, revenue, and subject staking",
          "Confirm in wallet",
          "Retry approval verification",
          "Retry confirmation",
          "AutolaunchSubjectPaymentWallet"
        ] do
      refute html =~ copy
    end
  end

  test "direct subject-payment lifecycle injection has no LiveView handler", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    for {event, params} <- @removed_events do
      {:ok, view, _html} = subject_live(conn, account, subject)

      assert_removed_event(view, event, params)
    end
  end

  defp subject_live(conn, account, subject) do
    conn
    |> init_test_session(%{human_account_id: account.id})
    |> live("/autolaunch/subjects/#{subject.subject_id}")
  end

  defp assert_removed_event(view, event, params) do
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      capture_log(fn -> assert catch_exit(render_hook(view, event, params)) end)
    after
      flush_exit_messages()
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  defp flush_exit_messages do
    receive do
      {:EXIT, _pid, _reason} -> flush_exit_messages()
    after
      0 -> :ok
    end
  end
end
