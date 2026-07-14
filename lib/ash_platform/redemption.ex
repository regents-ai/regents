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
    end
  end
end
