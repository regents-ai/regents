defmodule AshPlatform.StakingTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Staking

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"

  defmodule ChainStub do
    @behaviour AshPlatform.Staking.ChainClient

    @impl true
    def overview(wallet) do
      send(Process.get(:staking_test_pid, self()), {:overview, wallet})

      case Process.get(:overview_error) do
        nil -> {:ok, snapshot(wallet)}
        reason -> {:error, reason}
      end
    end

    @impl true
    def allowance(wallet, amount) do
      send(Process.get(:staking_test_pid, self()), {:allowance, wallet, amount})
      {:ok, Process.get(:allowance, :insufficient)}
    end

    defp snapshot(wallet) do
      %{
        chain_id: 8453,
        chain_label: "Base",
        block_number: 42,
        block_hash: "0x" <> String.duplicate("1b", 32),
        contract_address: "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5",
        paused: Process.get(:paused, false),
        total_staked: "100",
        total_staked_raw: "100000000000000000000",
        supply_denominator_raw: "1000000000000000000000",
        remaining_capacity_raw: Process.get(:capacity_raw, "900000000000000000000"),
        remaining_capacity: "900",
        available_regent_reward_inventory_raw: "250000000000000000000000",
        available_regent_reward_inventory: "250000",
        reserved_usdc_raw: "125000000000",
        reserved_usdc: "125000",
        emission_apr_bps: 1_200,
        emission_apr_percent: "12",
        wallet_address: wallet,
        wallet_token_balance_raw: positioned(wallet, :token_raw, "10000000000000000000"),
        wallet_token_balance: positioned(wallet, :token, "10"),
        wallet_usdc_balance_raw: positioned(wallet, :usdc_wallet_raw, "4250000"),
        wallet_usdc_balance: positioned(wallet, :usdc_wallet, "4.25"),
        wallet_stake_balance_raw: positioned(wallet, :stake_raw, "5000000000000000000"),
        wallet_stake_balance: positioned(wallet, :stake, "5"),
        wallet_claimable_usdc_raw: positioned(wallet, :claimable_usdc_raw, "1500000"),
        wallet_claimable_usdc: positioned(wallet, :claimable_usdc, "1.5"),
        wallet_claimable_regent_raw:
          positioned(wallet, :claimable_regent_raw, "2000000000000000000"),
        wallet_claimable_regent: positioned(wallet, :claimable_regent, "2"),
        wallet_funded_claimable_regent_raw:
          positioned(wallet, :funded_regent_raw, "2000000000000000000"),
        wallet_funded_claimable_regent: positioned(wallet, :funded_regent, "2")
      }
    end

    defp positioned(nil, _key, _default), do: nil
    defp positioned(_wallet, key, default), do: Process.get(key, default)
  end

  setup do
    previous_client = Application.get_env(:ash_platform, :staking_chain_client)
    Application.put_env(:ash_platform, :staking_chain_client, ChainStub)
    Process.put(:staking_test_pid, self())
    on_exit(fn -> restore_env(:staking_chain_client, previous_client) end)

    :ok
  end

  test "CHAIN_FACTS_ONLY: public and connected-wallet reads come directly from Base" do
    assert {:ok, %{chain_id: 8453, wallet_address: nil}} = Staking.overview()
    assert_receive {:overview, nil}
    assert {:ok, %{wallet_address: @wallet}} = Staking.account_for_wallet(@wallet)
    assert_receive {:overview, @wallet}
    assert {:ok, %{wallet_address: @other}} = Staking.account_for_wallet(@other)
    assert_receive {:overview, @other}
    assert {:error, _} = Staking.account_for_wallet("not-a-wallet")
  end

  test "FRESH_ACTION_ID: identical clicks create distinct direct wallet envelopes" do
    assert {:ok, first} = Staking.prepare_unstake(@wallet, "1")
    assert {:ok, second} = Staking.prepare_unstake(@wallet, "1")
    assert first.action == "unstake"
    assert second.action == "unstake"
    refute first.action_id == second.action_id
  end

  test "CURRENT_ALLOWANCE: a sufficient stake asks only for Stake" do
    Process.put(:allowance, :sufficient)
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1.25")
    assert envelope.action == "stake"
    assert envelope.approval == nil
    assert envelope.arguments.amount_atomic == "1250000000000000000"
    assert_receive {:allowance, @wallet, 1_250_000_000_000_000_000}
  end

  test "CURRENT_ALLOWANCE: an insufficient stake carries its exact approval" do
    Process.put(:allowance, :insufficient)
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1")
    assert envelope.approval.mode == "exact"
    assert envelope.approval.amount == "1000000000000000000"
    assert envelope.approval.spender == envelope.to
  end

  test "CURRENT_CHAIN_LIMITS: Base, not the server, decides amounts and claims" do
    Process.put(:token_raw, "1")
    assert {:ok, %{action: "stake"}} = Staking.prepare_stake(@wallet, "1")

    Process.put(:stake_raw, "1")
    assert {:ok, %{action: "unstake"}} = Staking.prepare_unstake(@wallet, "1")

    Process.put(:claimable_usdc_raw, "0")
    assert {:ok, %{action: "claim_usdc"}} = Staking.prepare_claim_usdc(@wallet)
  end

  test "ONLY_SHAPE_REFUSALS: amount shape and signer shape are the server's last two refusals" do
    assert {:error, _} = Staking.prepare_stake(@wallet, "0")
    assert {:error, _} = Staking.prepare_stake("not-a-wallet", "1")
  end

  test "EXACT_AMOUNTS: values are positive decimals with at most 18 places" do
    assert {:ok, 1_000_000_000_000_000_001} = Staking.parse_amount("1.000000000000000001")

    for invalid <- ["", "0", "-1", "1e3", "1.0000000000000000001", "NaN"] do
      assert {:error, :invalid_amount} = Staking.parse_amount(invalid)
    end
  end

  test "DIRECT_CONTROLS: every claim returns a sendable envelope without persisted state" do
    assert {:ok, %{action: "claim_usdc"}} = Staking.prepare_claim_usdc(@wallet)
    assert {:ok, %{action: "claim_regent"}} = Staking.prepare_claim_regent(@wallet)

    assert {:ok, %{action: "claim_and_restake_regent"}} =
             Staking.prepare_claim_and_restake_regent(@wallet)
  end

  test "PAUSED: Base, not the server, decides a claim while the contract is paused" do
    Process.put(:paused, true)

    assert {:ok, %{action: "claim_and_restake_regent"}} =
             Staking.prepare_claim_and_restake_regent(@wallet)

    assert {:ok, %{action: "claim_usdc"}} = Staking.prepare_claim_usdc(@wallet)
    assert {:ok, %{action: "claim_regent"}} = Staking.prepare_claim_regent(@wallet)
    assert {:ok, %{action: "unstake"}} = Staking.prepare_unstake(@wallet, "1")
  end

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
