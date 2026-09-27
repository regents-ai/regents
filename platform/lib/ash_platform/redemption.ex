defmodule AshPlatform.Redemption do
  @moduledoc "Canonical domain boundary for Animata redemption on Base."
  use Ash.Domain

  resources do
    resource AshPlatform.Redemption.Snapshot do
      define :overview, action: :overview

      define :account_for_wallet,
        action: :account_for_wallet,
        args: [:expected_signer, :collection, :token_id]
    end
  end

  # A display-only projection of the last reading from Base, used for the page's
  # stepper and its hint copy; the wallet steps never consult it.
  defdelegate next_step(facts, signer), to: AshPlatform.Redemption.Actions
end
