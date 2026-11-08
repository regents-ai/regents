defmodule Regents.Staking.UsdcClaimPropertyTest do
  # The page says a USDC claim waits on the treasury exactly when the staking
  # contract would revert it: when paying it would take the treasury's residual
  # below zero in `_recordUsdcClaim`.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Regents.Staking

  property "the shortfall reason holds exactly when the contract's claim would underflow" do
    check all({credited, claimed, residual, claimable} <- claim_figures(), max_runs: 2_000) do
      reading = %{
        wallet_claimable_usdc_raw: Integer.to_string(claimable),
        wallet_usdc_credited_raw: Integer.to_string(credited),
        wallet_usdc_claimed_raw: Integer.to_string(claimed),
        wallet_usdc_residual_raw: Integer.to_string(residual)
      }

      refusal = Staking.limit_refusal(reading, "claim_usdc", nil)

      assert refusal == :usdc_rewards_short ==
               (contract_claim(credited, claimed, residual, claimable) == :underflow)
    end
  end

  property "a figure that cannot be read gives no shortfall, only an unread reading" do
    check all(
            {credited, claimed, residual, claimable} <- claim_figures(),
            missing <-
              member_of([
                :wallet_claimable_usdc_raw,
                :wallet_usdc_credited_raw,
                :wallet_usdc_claimed_raw,
                :wallet_usdc_residual_raw
              ])
          ) do
      reading =
        Map.put(
          %{
            wallet_claimable_usdc_raw: Integer.to_string(claimable),
            wallet_usdc_credited_raw: Integer.to_string(credited),
            wallet_usdc_claimed_raw: Integer.to_string(claimed),
            wallet_usdc_residual_raw: Integer.to_string(residual)
          },
          missing,
          :unavailable
        )

      assert Staking.limit_refusal(reading, "claim_usdc", nil) == :chain_unavailable
    end
  end

  # `claimUSDC` and `_recordUsdcClaim` in RegentRevenueStaking.sol, with
  # Solidity's checked subtraction: nothing to claim returns early, and a claim
  # past what is credited and unpaid takes the overage from the residual.
  defp contract_claim(_credited, _claimed, _residual, amount) when amount < 1, do: :ok

  defp contract_claim(credited, claimed, residual, amount) do
    outstanding = credited - claimed

    if amount > outstanding and amount - outstanding > residual,
      do: :underflow,
      else: :ok
  end

  # The contract never pays out more than it credited, so what is claimed never
  # passes what is credited. Half the cases sit right at the edge, where a claim
  # is a few units either side of what the contract can pay.
  defp claim_figures do
    gen all(
          credited <- integer(0..1_000_000_000_000),
          claimed <- integer(0..credited),
          residual <- one_of([constant(0), integer(0..1_000_000_000)]),
          claimable <-
            one_of([
              integer(0..2_000_000_000_000),
              map(integer(-3..3), &max(credited - claimed + residual + &1, 0))
            ])
        ) do
      {credited, claimed, residual, claimable}
    end
  end
end
