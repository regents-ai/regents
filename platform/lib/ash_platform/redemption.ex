defmodule AshPlatform.Redemption do
  @moduledoc "Canonical domain boundary for Animata redemption on Base."
  use Ash.Domain

  resources do
    resource AshPlatform.Redemption.Snapshot do
      define :overview, action: :overview

      define :account_for_wallet,
        action: :account_for_wallet,
        args: [:expected_signer, :collection, :token_id]

      define :prepare_nft_approval,
        action: :prepare_nft_approval,
        args: [:expected_signer, :collection, :token_id]

      define :prepare_usdc_approval,
        action: :prepare_usdc_approval,
        args: [:expected_signer, :collection, :token_id]

      define :prepare_redeem,
        action: :prepare_redeem,
        args: [:expected_signer, :collection, :token_id]

      define :prepare_claim, action: :prepare_claim, args: [:expected_signer]
    end
  end

  # A display-only projection of the last reading from Base, used for the page's
  # stepper and its hint copy; preparing an action never consults it.
  defdelegate next_step(facts, signer), to: AshPlatform.Redemption.Actions
end
