defmodule AshPlatformWeb.AutolaunchSubjectPaymentLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.{Human, System}

  @wallet "0x1111111111111111111111111111111111111111"
  @token "0x2222222222222222222222222222222222222222"
  @splitter "0x3333333333333333333333333333333333333333"
  @ingress "0x4444444444444444444444444444444444444444"
  @treasury "0x5555555555555555555555555555555555555555"
  @factory "0x6666666666666666666666666666666666666666"
  @payment_link "0x7777777777777777777777777777777777777777"
  @replacement "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @other_payment_link "0x8888888888888888888888888888888888888888"
  @other_ingress "0x9999999999999999999999999999999999999999"
  @subject_id "0x" <> String.duplicate("53", 32)
  @hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)
  @now ~U[2026-07-31 12:00:00Z]

  defmodule ChainStub do
    @behaviour AshPlatform.Autolaunch.SubjectPaymentChainClient

    @impl true
    def confirm(envelope, hash, _approval_hash) do
      case Application.get_env(:ash_platform, :test_subject_payment_confirmation, :ok) do
        :ok ->
          result = %{transaction_hash: hash, receipt_verified: true}

          if envelope.action in ~w(create_payment_link create_canonical_payment_link) do
            receiver =
              Application.fetch_env!(:ash_platform, :test_subject_payment_created_receivers)
              |> Map.fetch!(envelope.arguments.label)

            {:ok, Map.put(result, :payment_link_receiver, receiver)}
          else
            {:ok, result}
          end

        :pending ->
          {:error, :transaction_pending}

        :reverted ->
          {:error, :transaction_reverted}
      end
    end

    @impl true
    def approval_status(_envelope, _hash) do
      {:ok, Application.get_env(:ash_platform, :test_subject_payment_approval, :success)}
    end
  end

  setup do
    previous_chain =
      Application.get_env(:ash_platform, :autolaunch_subject_payment_chain_client)

    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)

    Application.put_env(
      :ash_platform,
      :autolaunch_subject_payment_chain_client,
      ChainStub
    )

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> @now end)

    Application.put_env(:ash_platform, :test_subject_payment_created_receivers, %{
      "Recorded payment link" => @payment_link,
      "Other subject payment link" => @other_payment_link
    })

    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_subject_payment_confirmation)
      Application.delete_env(:ash_platform, :test_subject_payment_approval)
      Application.delete_env(:ash_platform, :test_subject_payment_created_receivers)
      restore(:autolaunch_subject_payment_chain_client, previous_chain)
      restore(:wallet_action_clock, previous_clock)
    end)

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

    actor = %Human{human_account_id: account.id}
    record_payment_link!(subject, actor, "Recorded payment link")

    %{account: account, subject: subject}
  end

  test "subject page reviews every S3 action from stored contract identities", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, html} = subject_live(conn, account, subject)

    assert has_element?(
             view,
             "#subject-payment-wallet[phx-hook='AutolaunchSubjectPaymentWallet']"
           )

    refute html =~ "Salt"
    refute has_element?(view, "[name='subject_payment[salt]']")

    reviews = [
      {"#subject-payment-link-create-form", %{label: "Sponsor", canonical: "false"},
       "create_payment_link", @factory},
      {"#subject-payment-link-create-form", %{label: "Official", canonical: "true"},
       "create_canonical_payment_link", @factory},
      {"#subject-payment-link-canonical-form", %{receiver: @payment_link, canonical: "true"},
       "set_payment_link_canonical", @factory},
      {"#subject-payment-link-state-form",
       %{receiver: @payment_link, active: "false", replacement: @replacement},
       "set_payment_link_receiver_state", @factory},
      {"#subject-ingress-sweep-form", %{}, "sweep_usdc", @ingress},
      {"#subject-stake-form", %{amount: "1.25", receiver: ""}, "stake", @splitter},
      {"#subject-unstake-form", %{amount: "0.5"}, "unstake", @splitter},
      {"#subject-claim-usdc-form", %{}, "claim_usdc", @splitter}
    ]

    for {selector, fields, action, target} <- reviews do
      view
      |> form(selector, subject_payment: fields)
      |> render_submit()

      assert has_element?(view, "#subject-payment-review")

      view
      |> element("#subject-payment-review button", "Confirm in wallet")
      |> render_click()

      assert_push_event(view, "autolaunch-subject-payment:prepared", %{envelope: envelope})
      assert envelope.action == action
      assert envelope.to == target
      assert envelope.expected_signer == @wallet
      assert envelope.value == "0"

      if action == "set_payment_link_receiver_state" do
        assert has_element?(
                 view,
                 "#subject-payment-review-replacement",
                 @replacement
               )
      end

      if action == "stake" do
        assert envelope.approval.mode == "exact"
        assert envelope.approval.amount == "1250000000000000000"
      end

      view
      |> element("#subject-payment-review button", "Cancel review")
      |> render_click()
    end
  end

  test "a second subject's payment-link receiver is rejected on the first subject's page", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    other_subject =
      Autolaunch.import_subject!(
        "0x" <> String.duplicate("54", 32),
        "agent",
        8453,
        @token,
        @splitter,
        @other_ingress,
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

    record_payment_link!(
      other_subject,
      %Human{human_account_id: account.id},
      "Other subject payment link"
    )

    {:ok, view, _html} = subject_live(conn, account, subject)

    view
    |> form("#subject-payment-link-canonical-form",
      subject_payment: %{receiver: @other_payment_link, canonical: "true"}
    )
    |> render_submit()

    assert render(view) =~ "could not be prepared"
    refute has_element?(view, "#subject-payment-review")
  end

  test "invalid server-validated admin input stays in product language", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, _html} = subject_live(conn, account, subject)

    view
    |> form("#subject-payment-link-canonical-form",
      subject_payment: %{receiver: "not-an-address", canonical: "true"}
    )
    |> render_submit()

    html = render(view)
    assert html =~ "could not be prepared"
    refute html =~ "invalid_address"
    refute has_element?(view, "#subject-payment-review")
  end

  test "a review with only 60 seconds left cannot open the wallet", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, _html} = subject_live(conn, account, subject)
    prepare_claim(view)

    Application.put_env(:ash_platform, :wallet_action_clock, fn ->
      DateTime.add(@now, 540, :second)
    end)

    view
    |> element("#subject-payment-review button", "Confirm in wallet")
    |> render_click()

    assert render(view) =~ "wallet review expired"
    refute_push_event(view, "autolaunch-subject-payment:prepared", %{})
  end

  test "submitted hash survives expiry and refresh for read-only confirmation", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, _html} = subject_live(conn, account, subject)
    prepare_claim(view)

    view
    |> element("#subject-payment-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-subject-payment:prepared", %{envelope: envelope})

    render_hook(view, "autolaunch_subject_payment_submitted", %{
      "action_id" => envelope.action_id,
      "phase" => "action",
      "transaction_hash" => @hash
    })

    Application.put_env(:ash_platform, :wallet_action_clock, fn ->
      DateTime.add(@now, 601, :second)
    end)

    {:ok, restored, _html} = subject_live(conn, account, subject)

    render_hook(restored, "restore_autolaunch_subject_payment_submission", %{
      "envelope" => envelope,
      "transaction_hash" => @hash
    })

    send(
      restored.pid,
      {:autolaunch_subject_payment_envelope_expired, envelope.action_id}
    )

    assert has_element?(restored, "#subject-payment-review", "Retry confirmation")

    render_hook(restored, "confirm_autolaunch_subject_payment", %{
      "action_id" => envelope.action_id,
      "transaction_hash" => @hash
    })

    render_async(restored)
    assert render(restored) =~ "Confirmed on Base"
    assert_push_event(restored, "autolaunch-subject-payment:confirmed", %{})
  end

  test "stake approval hash remains recoverable and receipt outcomes remain retryable", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, _html} = subject_live(conn, account, subject)

    view
    |> form("#subject-stake-form", subject_payment: %{amount: "1", receiver: ""})
    |> render_submit()

    view
    |> element("#subject-payment-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-subject-payment:prepared", %{envelope: envelope})

    render_hook(view, "autolaunch_subject_payment_submitted", %{
      "action_id" => envelope.action_id,
      "phase" => "approval",
      "transaction_hash" => @approval_hash
    })

    assert has_element?(view, "#subject-payment-review", "Retry approval verification")

    view
    |> element("#subject-payment-review button", "Retry approval verification")
    |> render_click()

    render_async(view)
    assert render(view) =~ "approval confirmed"

    Application.put_env(:ash_platform, :test_subject_payment_confirmation, :pending)

    render_hook(view, "autolaunch_subject_payment_submitted", %{
      "action_id" => envelope.action_id,
      "phase" => "action",
      "transaction_hash" => @hash
    })

    render_hook(view, "confirm_autolaunch_subject_payment", %{
      "action_id" => envelope.action_id,
      "approval_transaction_hash" => @approval_hash,
      "transaction_hash" => @hash
    })

    render_async(view)
    assert render(view) =~ "not confirmed yet"
    assert has_element?(view, "#subject-payment-review", "Retry confirmation")

    Application.put_env(:ash_platform, :test_subject_payment_confirmation, :reverted)

    view
    |> element("#subject-payment-review button", "Retry confirmation")
    |> render_click()

    render_async(view)
    assert render(view) =~ "subject transaction reverted"
    refute has_element?(view, "#subject-payment-review")
    assert_push_event(view, "autolaunch-subject-payment:reverted", %{})
  end

  defp subject_live(conn, account, subject) do
    conn
    |> init_test_session(%{human_account_id: account.id})
    |> live("/autolaunch/subjects/#{subject.subject_id}")
  end

  defp prepare_claim(view) do
    view
    |> form("#subject-claim-usdc-form", subject_payment: %{})
    |> render_submit()
  end

  defp record_payment_link!(subject, actor, label) do
    {:ok, envelope} =
      Autolaunch.prepare_subject_payment_link(
        subject.subject_id,
        @wallet,
        label,
        false,
        actor: actor
      )

    {:ok, %{payment_link: payment_link}} =
      Autolaunch.confirm_subject_payment_action(envelope, @hash, nil, actor: actor)

    payment_link
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
