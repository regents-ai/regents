defmodule AshPlatform.Staking do
  @moduledoc "Canonical domain boundary for REGENT staking on Base."
  use Ash.Domain

  resources do
    resource AshPlatform.Staking.Snapshot do
      define :overview, action: :overview
      define :account, action: :account
      define :account_for_wallet, action: :account_for_wallet, args: [:expected_signer]
      define :prepare_stake, action: :prepare_stake, args: [:expected_signer, :amount]
      define :prepare_unstake, action: :prepare_unstake, args: [:expected_signer, :amount]
      define :prepare_claim_usdc, action: :prepare_claim_usdc, args: [:expected_signer]
      define :prepare_claim_regent, action: :prepare_claim_regent, args: [:expected_signer]

      define :prepare_claim_and_restake_regent,
        action: :prepare_claim_and_restake_regent,
        args: [:expected_signer]
    end
  end

  # The two Stake rules a presenter needs, owned here so the page and the named
  # preparation action can only ever answer the same way.
  defdelegate limit_refusal(snapshot, action, amount), to: AshPlatform.Staking.Actions
  defdelegate spendable(snapshot, action), to: AshPlatform.Staking.Actions
  defdelegate available_claims(snapshot), to: AshPlatform.Staking.Actions
  defdelegate parse_amount(value), to: AshPlatform.Staking.Actions
end
