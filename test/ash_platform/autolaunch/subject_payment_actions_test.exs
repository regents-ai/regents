defmodule AshPlatform.Autolaunch.SubjectPaymentActionsTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch
  alias AshPlatform.Autolaunch.SubjectPaymentActions

  @subject_id "not-a-subject"
  @wallet "0x1111111111111111111111111111111111111111"
  @invalid_address "not-an-address"

  defmodule NoCallChain do
    @behaviour AshPlatform.Autolaunch.SubjectPaymentChainClient

    @impl true
    def confirm(_envelope, _transaction_hash, _approval_transaction_hash) do
      send(Process.get(:subject_payment_test_pid), :subject_payment_chain_called)
      {:error, :unexpected_chain_call}
    end

    @impl true
    def approval_status(_envelope, _transaction_hash) do
      send(Process.get(:subject_payment_test_pid), :subject_payment_chain_called)
      {:error, :unexpected_chain_call}
    end
  end

  setup do
    previous_chain =
      Application.get_env(:ash_platform, :autolaunch_subject_payment_chain_client)

    Application.put_env(
      :ash_platform,
      :autolaunch_subject_payment_chain_client,
      NoCallChain
    )

    Process.put(:subject_payment_test_pid, self())

    on_exit(fn ->
      restore(:autolaunch_subject_payment_chain_client, previous_chain)
      Process.delete(:subject_payment_test_pid)
    end)

    :ok
  end

  test "every internal preparation variant is quarantined before auth, lookup, or encoding" do
    for prepare <- internal_preparations() do
      assert prepare.() == {:error, :action_not_admitted}
    end

    refute_receive :subject_payment_chain_called
  end

  test "every public facade preparation variant is quarantined before auth, lookup, or encoding" do
    for prepare <- facade_preparations() do
      assert prepare.() == {:error, :action_not_admitted}
    end

    refute_receive :subject_payment_chain_called
  end

  test "the fixed gate wins even when actor, subject, and action inputs are invalid" do
    invalid_actor_preparations = [
      fn ->
        SubjectPaymentActions.prepare_payment_link(@subject_id, @invalid_address, :bad, :bad,
          actor: nil
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_payment_link_canonical(
          @subject_id,
          @invalid_address,
          @invalid_address,
          :bad,
          actor: nil
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_payment_link_state(
          @subject_id,
          @invalid_address,
          @invalid_address,
          :bad,
          @invalid_address,
          actor: nil
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_ingress_sweep(
          @subject_id,
          @invalid_address,
          @invalid_address,
          actor: nil
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_stake(@subject_id, @invalid_address, :bad, @invalid_address,
          actor: nil
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_unstake(@subject_id, @invalid_address, :bad, actor: nil)
      end,
      fn ->
        SubjectPaymentActions.prepare_claim_usdc(@subject_id, @invalid_address, actor: nil)
      end,
      fn ->
        Autolaunch.prepare_subject_stake(@subject_id, @invalid_address, :bad, @invalid_address,
          actor: nil
        )
      end
    ]

    for prepare <- invalid_actor_preparations do
      assert prepare.() == {:error, :action_not_admitted}
    end
  end

  defp internal_preparations do
    actor = %Human{human_account_id: Ash.UUID.generate()}

    [
      fn ->
        SubjectPaymentActions.prepare_payment_link(@subject_id, @wallet, "Sponsor", false,
          actor: actor
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_payment_link(@subject_id, @wallet, "Official", true,
          actor: actor
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_payment_link_canonical(
          @subject_id,
          @wallet,
          @invalid_address,
          true,
          actor: actor
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_payment_link_state(
          @subject_id,
          @wallet,
          @invalid_address,
          false,
          nil,
          actor: actor
        )
      end,
      fn ->
        SubjectPaymentActions.prepare_ingress_sweep(@subject_id, @wallet, @invalid_address,
          actor: actor
        )
      end,
      fn -> SubjectPaymentActions.prepare_stake(@subject_id, @wallet, "1", nil, actor: actor) end,
      fn -> SubjectPaymentActions.prepare_unstake(@subject_id, @wallet, "1", actor: actor) end,
      fn -> SubjectPaymentActions.prepare_claim_usdc(@subject_id, @wallet, actor: actor) end
    ]
  end

  defp facade_preparations do
    actor = %Human{human_account_id: Ash.UUID.generate()}

    [
      fn ->
        Autolaunch.prepare_subject_payment_link(@subject_id, @wallet, "Sponsor", false,
          actor: actor
        )
      end,
      fn ->
        Autolaunch.prepare_subject_payment_link(@subject_id, @wallet, "Official", true,
          actor: actor
        )
      end,
      fn ->
        Autolaunch.prepare_subject_payment_link_canonical(
          @subject_id,
          @wallet,
          @invalid_address,
          true,
          actor: actor
        )
      end,
      fn ->
        Autolaunch.prepare_subject_payment_link_state(
          @subject_id,
          @wallet,
          @invalid_address,
          false,
          nil,
          actor: actor
        )
      end,
      fn ->
        Autolaunch.prepare_subject_ingress_sweep(@subject_id, @wallet, @invalid_address,
          actor: actor
        )
      end,
      fn -> Autolaunch.prepare_subject_stake(@subject_id, @wallet, "1", nil, actor: actor) end,
      fn -> Autolaunch.prepare_subject_unstake(@subject_id, @wallet, "1", actor: actor) end,
      fn -> Autolaunch.prepare_subject_claim_usdc(@subject_id, @wallet, actor: actor) end
    ]
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
