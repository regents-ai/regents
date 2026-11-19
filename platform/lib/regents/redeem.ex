defmodule Regents.Redeem do
  @moduledoc "Canonical domain boundary for Animata redemption on Base."
  use Boundary, top_level?: true, deps: [Regents, Regents.Chain], exports: [Steps]

  use Ash.Domain

  resources do
    resource Regents.Redeem.Snapshot do
      define :overview, action: :overview

      define :account_for_wallet,
        action: :account_for_wallet,
        args: [:expected_signer, :collection, :token_id]
    end
  end

  # A display-only projection of the last reading from Base, used for the page's
  # stepper and its hint copy; the wallet steps never consult it.
  defdelegate next_step(facts, signer), to: Regents.Redeem.Actions

  @doc "`:ok` when the redemption reading from Base answers. Not used yet."
  def health do
    with {:ok, _facts} <- overview(), do: :ok
  end
end
