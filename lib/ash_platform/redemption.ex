defmodule AshPlatform.Redemption do
  @moduledoc "Canonical domain boundary for Animata redemption on Base."
  use Ash.Domain

  resources do
    resource AshPlatform.Redemption.Snapshot do
      define :overview, action: :overview
      define :account, action: :account, args: [:collection, :token_id]

      define :prepare_nft_approval,
        action: :prepare_nft_approval,
        args: [:expected_signer, :collection]

      define :prepare_usdc_approval,
        action: :prepare_usdc_approval,
        args: [:expected_signer]

      define :prepare_redeem,
        action: :prepare_redeem,
        args: [:expected_signer, :collection, :token_id]

      define :prepare_claim, action: :prepare_claim, args: [:expected_signer]

      define :confirm_wallet_action,
        action: :confirm_wallet_action,
        args: [:envelope, :transaction_hash]

      define :restore_submitted_action,
        action: :restore_submitted_action,
        args: [:envelope]

      define :claim_wallet_dispatch, action: :claim_wallet_dispatch, args: [:action_id]

      define :bind_submitted_hash,
        action: :bind_submitted_hash,
        args: [:action_id, :transaction_hash]

      define :close_not_sent, action: :close_not_sent, args: [:action_id]
      define :cancel_operation, action: :cancel_operation, args: [:action_id]
      define :active_operation, action: :active_operation
    end

    # The shared operation resource carries no domain of its own; Redemption owns
    # every Redeem call against it and Staking owns every Stake call.
    resource AshPlatform.WalletActions.StakeRedeemOperation
  end
end
