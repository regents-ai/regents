defmodule AshPlatform.Autolaunch.SubjectPaymentActionsTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Autolaunch.PaymentLink
  alias AshPlatform.WalletActions.{Envelope, SubjectPaymentAbi}

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @token "0x3333333333333333333333333333333333333333"
  @splitter "0x4444444444444444444444444444444444444444"
  @ingress "0x5555555555555555555555555555555555555555"
  @treasury "0x6666666666666666666666666666666666666666"
  @factory "0x7777777777777777777777777777777777777777"
  @payment_link "0x8888888888888888888888888888888888888888"
  @other_payment_link "0x9999999999999999999999999999999999999999"
  @created_payment_link "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @canonical_payment_link "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  @unrecorded_payment_link "0xcccccccccccccccccccccccccccccccccccccccc"
  @other_ingress "0xdddddddddddddddddddddddddddddddddddddddd"
  @subject_id "0x" <> String.duplicate("53", 32)
  @hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)
  @now ~U[2026-07-31 12:00:00Z]

  defmodule ChainStub do
    @behaviour AshPlatform.Autolaunch.SubjectPaymentChainClient

    @impl true
    def confirm(envelope, hash, approval_hash) do
      send(Process.get(:subject_payment_test_pid), {:confirm, envelope, hash, approval_hash})

      case Process.get(:subject_payment_confirmation, :ok) do
        :ok ->
          result = %{transaction_hash: hash, receipt_verified: true}

          if envelope.action in ~w(create_payment_link create_canonical_payment_link) do
            receiver =
              Process.get(:subject_payment_created_receivers)
              |> Map.fetch!(envelope.arguments.label)

            {:ok, Map.put(result, :payment_link_receiver, receiver)}
          else
            {:ok, result}
          end

        :reverted ->
          {:error, :transaction_reverted}

        :pending ->
          {:error, :transaction_pending}
      end
    end

    @impl true
    def approval_status(envelope, hash) do
      send(Process.get(:subject_payment_test_pid), {:approval_status, envelope, hash})
      {:ok, Process.get(:subject_payment_approval_status, :success)}
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
    Process.put(:subject_payment_test_pid, self())

    Process.put(:subject_payment_created_receivers, %{
      "Recorded payment link" => @payment_link,
      "Sponsor" => @created_payment_link,
      "Official" => @canonical_payment_link,
      "Other subject payment link" => @other_payment_link
    })

    on_exit(fn ->
      restore(:autolaunch_subject_payment_chain_client, previous_chain)
      restore(:wallet_action_clock, previous_clock)
      Process.delete(:subject_payment_test_pid)
      Process.delete(:subject_payment_confirmation)
      Process.delete(:subject_payment_approval_status)
      Process.delete(:subject_payment_created_receivers)
    end)

    account =
      Accounts.register_verified!(
        "did:privy:s3-subject-payment",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    other_account =
      Accounts.register_verified!(
        "did:privy:s3-subject-payment-other",
        @other,
        [@other],
        actor: %System{}
      )

    subject = subject!()
    actor = %Human{human_account_id: account.id}
    payment_link = record_payment_link!(subject, actor, "Recorded payment link")
    flush_confirm_message()

    %{
      actor: actor,
      other_actor: %Human{human_account_id: other_account.id},
      subject: subject,
      payment_link: payment_link
    }
  end

  test "prepares every implementation-proven action with explicit stored identity", %{
    actor: actor,
    subject: subject
  } do
    envelopes = prepare_all(subject, actor)

    assert Enum.map(envelopes, &{&1.resource, &1.action, &1.to}) == [
             {"autolaunch_payment_link", "create_payment_link", @factory},
             {"autolaunch_payment_link", "create_canonical_payment_link", @factory},
             {"autolaunch_payment_link", "set_payment_link_canonical", @factory},
             {"autolaunch_payment_link", "set_payment_link_receiver_state", @factory},
             {"autolaunch_ingress", "sweep_usdc", @ingress},
             {"autolaunch_subject_staking", "stake", @splitter},
             {"autolaunch_subject_staking", "unstake", @splitter},
             {"autolaunch_subject_staking", "claim_usdc", @splitter}
           ]

    assert Enum.map(envelopes, &String.slice(&1.data, 0, 10)) == [
             "0x96bc6c1a",
             "0xb12d629e",
             "0x706a7fa6",
             "0xc8c05f99",
             "0xbe25fb30",
             "0x7acb7757",
             "0x8381e182",
             "0x42852610"
           ]

    for envelope <- envelopes do
      assert envelope.chain_id == 8453
      assert envelope.expected_signer == @wallet
      assert envelope.value == "0"
      assert envelope.arguments.subject_id == subject.subject_id
      assert Envelope.valid?(envelope)
    end
  end

  test "always generates a unique random salt and keeps it outside the public preparation surface",
       %{
         actor: actor,
         subject: subject
       } do
    refute function_exported?(Autolaunch, :prepare_subject_payment_link, 6)

    {:ok, first} =
      Autolaunch.prepare_subject_payment_link(
        subject.subject_id,
        @wallet,
        "Sponsor",
        false,
        actor: actor
      )

    {:ok, second} =
      Autolaunch.prepare_subject_payment_link(
        subject.subject_id,
        @wallet,
        "Sponsor",
        false,
        actor: actor
      )

    assert first.arguments.salt =~ ~r/^0x[0-9a-f]{64}$/
    assert second.arguments.salt =~ ~r/^0x[0-9a-f]{64}$/
    refute first.arguments.salt == second.arguments.salt

    assert {:error, :invalid_label} =
             Autolaunch.prepare_subject_payment_link(
               subject.subject_id,
               @wallet,
               "   ",
               false,
               actor: actor
             )

    assert_raise ArgumentError, fn -> SubjectPaymentAbi.encode_ingress_sweep("not-bytes32") end
  end

  test "binds payment-link admin actions to recorded receivers and rejects ingress, unrecorded, cross-subject, and self replacement",
       %{
         actor: actor,
         subject: subject
       } do
    other_subject =
      subject!(
        subject_id: "0x" <> String.duplicate("54", 32),
        ingress_address: @other_ingress
      )

    record_payment_link!(other_subject, actor, "Other subject payment link")

    assert {:ok, envelope} =
             Autolaunch.prepare_subject_payment_link_canonical(
               subject.subject_id,
               @wallet,
               @payment_link,
               true,
               actor: actor
             )

    assert envelope.arguments.receiver == @payment_link

    for rejected <- [@unrecorded_payment_link, @ingress, @other_payment_link] do
      assert {:error, :payment_link_receiver_not_recorded} =
               Autolaunch.prepare_subject_payment_link_canonical(
                 subject.subject_id,
                 @wallet,
                 rejected,
                 true,
                 actor: actor
               )
    end

    assert {:error, :replacement_matches_receiver} =
             Autolaunch.prepare_subject_payment_link_state(
               subject.subject_id,
               @wallet,
               @payment_link,
               false,
               @payment_link,
               actor: actor
             )
  end

  test "payment-link records are normalized confirmation-only writes", %{
    actor: actor,
    payment_link: payment_link,
    subject: subject
  } do
    assert payment_link.receiver_address == @payment_link
    assert payment_link.label == "Recorded payment link"
    assert payment_link.created_at

    assert {:error, %Ash.Error.Forbidden{}} =
             PaymentLink
             |> Ash.Changeset.for_create(
               :record_confirmation,
               %{
                 subject_id: subject.id,
                 receiver_address: @unrecorded_payment_link,
                 label: "Bypass"
               },
               actor: actor
             )
             |> Ash.create()
  end

  test "server-validates payment-link addresses and booleans", %{
    actor: actor,
    subject: subject
  } do
    assert {:error, :invalid_address} =
             Autolaunch.prepare_subject_payment_link_canonical(
               subject.subject_id,
               @wallet,
               "not-an-address",
               true,
               actor: actor
             )

    assert {:error, :invalid_boolean} =
             Autolaunch.prepare_subject_payment_link_canonical(
               subject.subject_id,
               @wallet,
               @payment_link,
               "true",
               actor: actor
             )

    assert {:error, :invalid_address} =
             Autolaunch.prepare_subject_payment_link_state(
               subject.subject_id,
               @wallet,
               @payment_link,
               false,
               "not-an-address",
               actor: actor
             )
  end

  test "rejects ingress targets outside the subject's recorded account allowlist", %{
    actor: actor,
    subject: subject
  } do
    assert {:error, :ingress_not_recorded} =
             Autolaunch.prepare_subject_ingress_sweep(
               subject.subject_id,
               @wallet,
               @other,
               actor: actor
             )

    lookalike = String.slice(@ingress, 0, byte_size(@ingress) - 1) <> "4"

    assert {:error, :ingress_not_recorded} =
             Autolaunch.prepare_subject_ingress_sweep(
               subject.subject_id,
               @wallet,
               lookalike,
               actor: actor
             )

    assert {:ok, envelope} =
             Autolaunch.prepare_subject_ingress_sweep(
               subject.subject_id,
               @wallet,
               "0x" <> (@ingress |> String.trim_leading("0x") |> String.upcase()),
               actor: actor
             )

    assert envelope.to == @ingress
  end

  test "stake approval is exact for the stored subject token and splitter", %{
    actor: actor,
    subject: subject
  } do
    assert {:ok, envelope} =
             Autolaunch.prepare_subject_stake(
               subject.subject_id,
               @wallet,
               "1.25",
               @other,
               actor: actor
             )

    assert envelope.arguments.amount_atomic == "1250000000000000000"
    assert envelope.arguments.receiver == @other

    assert envelope.approval == %{
             token: @token,
             spender: @splitter,
             amount: "1250000000000000000",
             data: SubjectPaymentAbi.encode_approval(@splitter, 1_250_000_000_000_000_000),
             mode: "exact"
           }

    assert {:error, :invalid_amount_precision} =
             Autolaunch.prepare_subject_stake(
               subject.subject_id,
               @wallet,
               "0.0000000000000000001",
               actor: actor
             )
  end

  test "enforces verified signer and stored subject ownership on every preparation", %{
    actor: actor,
    other_actor: other_actor,
    subject: subject
  } do
    for prepare <- preparation_functions(subject) do
      assert {:error, :wrong_signer} = prepare.(actor, @other)
      assert {:error, :not_subject_owner} = prepare.(other_actor, @other)
    end
  end

  test "rejects chain 1 at preparation for every action", %{actor: actor} do
    subject = subject!(subject_id: "0x" <> String.duplicate("01", 32), chain_id: 1)

    for prepare <- preparation_functions(subject) do
      assert {:error, :unsupported_chain} = prepare.(actor, @wallet)
    end
  end

  test "all submitted envelopes remain confirmable after expiry with current stored identity", %{
    actor: actor,
    subject: subject
  } do
    envelopes = prepare_all(subject, actor)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> DateTime.add(@now, 601) end)

    for envelope <- envelopes do
      refute Envelope.valid?(envelope)
      approval_hash = if envelope.approval, do: @approval_hash, else: nil

      assert {:ok, %{receipt_verified: true, subject: refreshed}} =
               Autolaunch.confirm_subject_payment_action(
                 envelope,
                 @hash,
                 approval_hash,
                 actor: actor
               )

      assert refreshed.subject_id == subject.subject_id
      assert_received {:confirm, ^envelope, @hash, ^approval_hash}
    end
  end

  test "confirmation fails closed on identity drift, wrong owner, and wrong signer", %{
    actor: actor,
    other_actor: other_actor,
    subject: subject
  } do
    {:ok, envelope} =
      Autolaunch.prepare_subject_payment_link(
        subject.subject_id,
        @wallet,
        "Sponsor",
        false,
        actor: actor
      )

    assert {:error, :stale_or_invalid_action} =
             Autolaunch.confirm_subject_payment_action(
               %{envelope | to: @other},
               @hash,
               nil,
               actor: actor
             )

    assert {:error, :wrong_signer} =
             Autolaunch.confirm_subject_payment_action(
               envelope,
               @hash,
               nil,
               actor: other_actor
             )

    changed = %{envelope | expected_signer: @other}

    assert {:error, :not_subject_owner} =
             Autolaunch.confirm_subject_payment_action(
               changed,
               @hash,
               nil,
               actor: other_actor
             )

    refute_received {:confirm, _, _, _}
  end

  test "confirmation distinguishes reverted and pending stub results", %{
    actor: actor,
    subject: subject
  } do
    {:ok, envelope} =
      Autolaunch.prepare_subject_claim_usdc(subject.subject_id, @wallet, actor: actor)

    Process.put(:subject_payment_confirmation, :reverted)

    assert {:ok, %{receipt_verified: true, transaction_reverted: true}} =
             Autolaunch.confirm_subject_payment_action(envelope, @hash, nil, actor: actor)

    Process.put(:subject_payment_confirmation, :pending)

    assert {:error, :transaction_pending} =
             Autolaunch.confirm_subject_payment_action(envelope, @hash, nil, actor: actor)
  end

  test "approval verification uses only the injected chain stub", %{
    actor: actor,
    subject: subject
  } do
    {:ok, envelope} =
      Autolaunch.prepare_subject_stake(subject.subject_id, @wallet, "1", actor: actor)

    assert {:ok, :success} =
             Autolaunch.verify_subject_payment_approval(
               envelope,
               @approval_hash,
               actor: actor
             )

    assert_received {:approval_status, ^envelope, @approval_hash}
  end

  defp prepare_all(subject, actor) do
    [
      Autolaunch.prepare_subject_payment_link(
        subject.subject_id,
        @wallet,
        "Sponsor",
        false,
        actor: actor
      ),
      Autolaunch.prepare_subject_payment_link(
        subject.subject_id,
        @wallet,
        "Official",
        true,
        actor: actor
      ),
      Autolaunch.prepare_subject_payment_link_canonical(
        subject.subject_id,
        @wallet,
        @payment_link,
        true,
        actor: actor
      ),
      Autolaunch.prepare_subject_payment_link_state(
        subject.subject_id,
        @wallet,
        @payment_link,
        false,
        nil,
        actor: actor
      ),
      Autolaunch.prepare_subject_ingress_sweep(
        subject.subject_id,
        @wallet,
        @ingress,
        actor: actor
      ),
      Autolaunch.prepare_subject_stake(subject.subject_id, @wallet, "1.25", actor: actor),
      Autolaunch.prepare_subject_unstake(subject.subject_id, @wallet, "0.5", actor: actor),
      Autolaunch.prepare_subject_claim_usdc(subject.subject_id, @wallet, actor: actor)
    ]
    |> Enum.map(fn {:ok, envelope} -> envelope end)
  end

  defp preparation_functions(subject) do
    [
      fn actor, signer ->
        Autolaunch.prepare_subject_payment_link(
          subject.subject_id,
          signer,
          "Sponsor",
          false,
          actor: actor
        )
      end,
      fn actor, signer ->
        Autolaunch.prepare_subject_payment_link(
          subject.subject_id,
          signer,
          "Official",
          true,
          actor: actor
        )
      end,
      fn actor, signer ->
        Autolaunch.prepare_subject_payment_link_canonical(
          subject.subject_id,
          signer,
          @payment_link,
          true,
          actor: actor
        )
      end,
      fn actor, signer ->
        Autolaunch.prepare_subject_payment_link_state(
          subject.subject_id,
          signer,
          @payment_link,
          true,
          nil,
          actor: actor
        )
      end,
      fn actor, signer ->
        Autolaunch.prepare_subject_ingress_sweep(
          subject.subject_id,
          signer,
          @ingress,
          actor: actor
        )
      end,
      fn actor, signer ->
        Autolaunch.prepare_subject_stake(subject.subject_id, signer, "1", actor: actor)
      end,
      fn actor, signer ->
        Autolaunch.prepare_subject_unstake(subject.subject_id, signer, "1", actor: actor)
      end,
      fn actor, signer ->
        Autolaunch.prepare_subject_claim_usdc(subject.subject_id, signer, actor: actor)
      end
    ]
  end

  defp subject!(overrides \\ []) do
    Autolaunch.import_subject!(
      Keyword.get(overrides, :subject_id, @subject_id),
      "agent",
      Keyword.get(overrides, :chain_id, 8453),
      @token,
      @splitter,
      Keyword.get(overrides, :ingress_address, @ingress),
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

    {:ok, result} =
      Autolaunch.confirm_subject_payment_action(envelope, @hash, nil, actor: actor)

    result.payment_link
  end

  defp flush_confirm_message do
    receive do
      {:confirm, _envelope, _hash, _approval_hash} -> :ok
    after
      0 -> :ok
    end
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
