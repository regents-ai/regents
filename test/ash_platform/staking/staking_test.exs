defmodule AshPlatform.StakingTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Staking}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.WalletActions.Envelope

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"

  defmodule ChainStub do
    @behaviour AshPlatform.Staking.ChainClient

    @impl true
    def overview(wallet) do
      send(self_or_test(), {:overview, wallet})

      {:ok,
       %{
         chain_id: 8453,
         chain_label: "Base",
         contract_address: "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5",
         paused: false,
         total_staked: "100",
         total_staked_raw: "100000000000000000000",
         wallet_address: wallet,
         wallet_token_balance: if(wallet, do: "10", else: nil),
         wallet_usdc_balance: if(wallet, do: "4.25", else: nil),
         wallet_stake_balance: if(wallet, do: "5", else: nil),
         wallet_claimable_usdc: if(wallet, do: "1.5", else: nil),
         wallet_claimable_regent_raw: if(wallet, do: "2000000000000000000", else: nil),
         wallet_claimable_regent: if(wallet, do: "2", else: nil),
         wallet_funded_claimable_regent_raw:
           if(wallet, do: Process.get(:funded_regent_raw, "2000000000000000000"), else: nil),
         wallet_funded_claimable_regent: if(wallet, do: "2", else: nil)
       }}
    end

    @impl true
    def confirm(envelope, hash, approval_hash) do
      send(self_or_test(), {:confirm, envelope, hash, approval_hash})

      overview(envelope.expected_signer)
      |> then(fn {:ok, staking} -> {:ok, %{transaction_hash: hash, staking: staking}} end)
    end

    @impl true
    def approval_status(_envelope, _hash), do: {:ok, Process.get(:approval_status, :reverted)}

    defp self_or_test, do: Process.get(:staking_test_pid, self())
  end

  setup do
    previous_client = Application.get_env(:ash_platform, :staking_chain_client)
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)
    test_pid = self()

    Application.put_env(:ash_platform, :staking_chain_client, ChainStub)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-10 12:00:00Z] end)
    Process.put(:staking_test_pid, test_pid)

    on_exit(fn ->
      restore_env(:staking_chain_client, previous_client)
      restore_env(:wallet_action_clock, previous_clock)
    end)

    {:ok, account} =
      Accounts.register_verified("did:privy:staking", @wallet, [@wallet], actor: %System{})

    %{actor: %Human{human_account_id: account.id}}
  end

  test "public overview reads chain truth without a wallet" do
    assert {:ok, %{chain_id: 8453, wallet_address: nil}} = Staking.overview()
    assert_receive {:overview, nil}
  end

  test "account reads are scoped to the verified connected wallet", %{actor: actor} do
    assert {:ok, %{wallet_address: @wallet}} = Staking.account(actor: actor)
    assert_receive {:overview, @wallet}
    assert {:error, _error} = Staking.account()
  end

  test "stake preparation binds signer, exact approval and ABI calldata", %{actor: actor} do
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1.5", actor: actor)

    assert envelope.chain_id == 8453
    assert envelope.to == "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
    assert envelope.value == "0"
    assert envelope.expected_signer == @wallet
    assert envelope.action == "stake"
    assert envelope.idempotency_key == envelope.action_id

    assert envelope.data ==
             "0x7acb7757" <>
               String.pad_leading(
                 Integer.to_string(1_500_000_000_000_000_000, 16) |> String.downcase(),
                 64,
                 "0"
               ) <>
               String.pad_leading(String.trim_leading(@wallet, "0x"), 64, "0")

    assert envelope.approval.amount == "1500000000000000000"
    assert envelope.approval.mode == "exact"
    assert Envelope.valid?(envelope)
  end

  test "the remaining four preparations use only the connected wallet", %{actor: actor} do
    assert {:ok, unstake} = Staking.prepare_unstake(@wallet, "2", actor: actor)
    assert String.starts_with?(unstake.data, "0x8381e182")

    assert {:ok, usdc} = Staking.prepare_claim_usdc(@wallet, actor: actor)
    assert String.starts_with?(usdc.data, "0x42852610")

    assert {:ok, regent} = Staking.prepare_claim_regent(@wallet, actor: actor)
    assert String.starts_with?(regent.data, "0x739c8d0d")

    assert {:ok, restake} = Staking.prepare_claim_and_restake_regent(@wallet, actor: actor)
    assert restake.data == "0xe72a8732"
    assert restake.risk_copy =~ "only when you choose"
  end

  test "wrong signer and invalid amounts fail closed", %{actor: actor} do
    assert {:error, _error} = Staking.prepare_stake(@other, "1", actor: actor)
    assert {:error, _error} = Staking.prepare_stake(@wallet, "0", actor: actor)

    assert {:error, _error} =
             Staking.prepare_stake(@wallet, "1.0000000000000000001", actor: actor)
  end

  test "earned REGENT cannot be claimed or reinvested while reward inventory is unfunded", %{
    actor: actor
  } do
    Process.put(:funded_regent_raw, "0")

    assert {:error, _error} = Staking.prepare_claim_regent(@wallet, actor: actor)
    assert {:error, _error} = Staking.prepare_claim_and_restake_regent(@wallet, actor: actor)
    Process.delete(:funded_regent_raw)
  end

  test "confirmation accepts an expired submitted envelope but refuses any drift", %{
    actor: actor
  } do
    {:ok, envelope} = Staking.prepare_claim_usdc(@wallet, actor: actor)
    hash = "0x" <> String.duplicate("ab", 32)

    assert {:ok, %{transaction_hash: ^hash, staking: %{wallet_address: @wallet}}} =
             Staking.confirm_wallet_action(envelope, hash, nil, actor: actor)

    assert_receive {:confirm, ^envelope, ^hash, nil}

    refute Envelope.valid?(%{envelope | data: "0xdeadbeef"})
    refute Envelope.valid?(%{envelope | action: "claim_regent"})
    refute Envelope.valid?(%{envelope | to: @other})
    refute Envelope.valid?(%{envelope | expected_signer: @other})
    refute Envelope.valid?(%{envelope | approval: %{mode: "unlimited"}})

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-10 12:11:00Z] end)
    refute Envelope.valid?(envelope)
    assert Envelope.valid_for_confirmation?(envelope)

    assert {:ok, %{transaction_hash: ^hash}} =
             Staking.confirm_wallet_action(envelope, hash, nil, actor: actor)

    assert_receive {:confirm, ^envelope, ^hash, nil}

    assert {:error, _error} =
             Staking.confirm_wallet_action(%{envelope | data: "0xdeadbeef"}, hash, nil,
               actor: actor
             )

    refute_receive {:confirm, _, _, _}
  end

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
