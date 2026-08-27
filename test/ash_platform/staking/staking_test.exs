defmodule AshPlatform.StakingTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Staking}
  alias AshPlatform.Actors.{Human, System}

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

    {:ok, account} =
      Accounts.register_verified("did:privy:staking", @wallet, [@wallet], actor: %System{})

    %{account: account, actor: %Human{human_account_id: account.id}, opts: leased(account.id)}
  end

  test "CHAIN_FACTS_ONLY: public and linked-wallet reads come directly from Base", %{
    actor: actor,
    opts: opts
  } do
    assert {:ok, %{chain_id: 8453, wallet_address: nil}} = Staking.overview()
    assert_receive {:overview, nil}
    assert {:ok, %{wallet_address: @wallet}} = Staking.account_for_wallet(@wallet, opts)
    assert_receive {:overview, @wallet}
    assert {:error, _} = Staking.account_for_wallet(@other, opts)
    assert {:error, _} = Staking.account_for_wallet(@wallet, actor: actor)
    assert {:error, _} = Staking.account_for_wallet(@wallet)
  end

  test "FRESH_ACTION_ID: identical clicks create distinct direct wallet envelopes", %{opts: opts} do
    assert {:ok, first} = Staking.prepare_unstake(@wallet, "1", opts)
    assert {:ok, second} = Staking.prepare_unstake(@wallet, "1", opts)
    assert first.action == "unstake"
    assert second.action == "unstake"
    refute first.action_id == second.action_id
  end

  test "CURRENT_ALLOWANCE: a sufficient stake asks only for Stake", %{opts: opts} do
    Process.put(:allowance, :sufficient)
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1.25", opts)
    assert envelope.action == "stake"
    assert envelope.approval == nil
    assert envelope.arguments.amount_atomic == "1250000000000000000"
    assert_receive {:allowance, @wallet, 1_250_000_000_000_000_000}
  end

  test "CURRENT_ALLOWANCE: an insufficient stake carries its exact approval", %{opts: opts} do
    Process.put(:allowance, :insufficient)
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1", opts)
    assert envelope.approval.mode == "exact"
    assert envelope.approval.amount == "1000000000000000000"
    assert envelope.approval.spender == envelope.to
  end

  test "CURRENT_CHAIN_LIMITS: amounts and claims are refused from fresh Base facts", %{opts: opts} do
    Process.put(:token_raw, "1")
    assert {:error, error} = Staking.prepare_stake(@wallet, "1", opts)
    assert refusal(error) == :amount_above_balance

    Process.put(:stake_raw, "1")
    assert {:error, error} = Staking.prepare_unstake(@wallet, "1", opts)
    assert refusal(error) == :amount_above_stake

    Process.put(:claimable_usdc_raw, "0")
    assert {:error, error} = Staking.prepare_claim_usdc(@wallet, opts)
    assert refusal(error) == :no_claimable_usdc
  end

  test "EXACT_AMOUNTS: values are positive decimals with at most 18 places" do
    assert {:ok, 1_000_000_000_000_000_001} = Staking.parse_amount("1.000000000000000001")

    for invalid <- ["", "0", "-1", "1e3", "1.0000000000000000001", "NaN"] do
      assert {:error, :invalid_amount} = Staking.parse_amount(invalid)
    end
  end

  test "DIRECT_CONTROLS: every claim returns a sendable envelope without persisted state", %{
    opts: opts
  } do
    assert {:ok, %{action: "claim_usdc"}} = Staking.prepare_claim_usdc(@wallet, opts)
    assert {:ok, %{action: "claim_regent"}} = Staking.prepare_claim_regent(@wallet, opts)

    assert {:ok, %{action: "claim_and_restake_regent"}} =
             Staking.prepare_claim_and_restake_regent(@wallet, opts)
  end

  defp refusal(%Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{reason: reason} | _]}),
    do: reason

  defp refusal(_), do: nil
  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
