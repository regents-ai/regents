defmodule AshPlatform.Names do
  @moduledoc "Read-only access to preserved historical names. No minting or entitlement mutations."
  use Ash.Domain

  resources do
    resource AshPlatform.Names.Claim do
      define :list_my_claims, action: :mine
    end
  end

  @doc "Recorded name evidence only; payment and entitlement fields remain private."
  def present(claim) do
    %{
      id: Integer.to_string(claim.id),
      name: claim.fqdn,
      ens_name: claim.ens_fqdn,
      owner_address: claim.owner_address,
      status: claim.claim_status,
      transaction: claim.tx_hash,
      ens_transaction: claim.ens_tx_hash,
      claimed_at: claim.created_at,
      ens_assigned_at: claim.ens_assigned_at
    }
  end
end
