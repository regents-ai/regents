defmodule AshPlatform.Staking do
  @moduledoc "Canonical domain boundary for REGENT staking on Base."
  use Ash.Domain

  resources do
    resource AshPlatform.Staking.Snapshot do
      define :overview, action: :overview
      define :account, action: :account
      define :prepare_stake, action: :prepare_stake, args: [:expected_signer, :amount]
      define :prepare_unstake, action: :prepare_unstake, args: [:expected_signer, :amount]
      define :prepare_claim_usdc, action: :prepare_claim_usdc, args: [:expected_signer]
      define :prepare_claim_regent, action: :prepare_claim_regent, args: [:expected_signer]

      define :prepare_claim_and_restake_regent,
        action: :prepare_claim_and_restake_regent,
        args: [:expected_signer]

      define :confirm_wallet_action,
        action: :confirm_wallet_action,
        args: [:envelope, :transaction_hash, :approval_transaction_hash]

      define :restore_submitted_action,
        action: :restore_submitted_action,
        args: [:envelope]

      define :verify_approval_submission,
        action: :verify_approval_submission,
        args: [:envelope, :transaction_hash]

      define :claim_wallet_dispatch, action: :claim_wallet_dispatch, args: [:action_id, :phase]

      define :bind_submitted_hash,
        action: :bind_submitted_hash,
        args: [:action_id, :phase, :transaction_hash]

      define :close_not_sent, action: :close_not_sent, args: [:action_id, :phase]
      define :cancel_operation, action: :cancel_operation, args: [:action_id]
      define :active_operation, action: :active_operation
    end

    # The shared operation resource carries no domain of its own; Staking owns
    # every Stake call against it and Redemption owns every Redeem call.
    resource AshPlatform.WalletActions.StakeRedeemOperation
  end

  def refresh_position(opts), do: account(opts)
end
