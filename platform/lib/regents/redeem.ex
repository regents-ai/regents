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

  @doc """
  Always `:ok`: Redeem keeps no reading on this site (each page reads Base when it
  opens), and a health read buys no chain read. Base answering for regents.sh is
  Stake's stored reading (`Regents.Stake.health/0`).
  """
  def health, do: :ok
end
