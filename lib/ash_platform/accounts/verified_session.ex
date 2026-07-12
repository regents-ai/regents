defmodule AshPlatform.Accounts.VerifiedSession do
  @moduledoc "Exchanges verified Privy evidence for the canonical human account."

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System

  def establish(%AshPlatform.VerifiedPrivyIdentity{privy_user_id: did} = verified)
      when is_binary(did) and did != "" do
    actor = %System{}

    case Accounts.get_by_privy_did(did, actor: actor) do
      {:ok, nil} ->
        with {:ok, account} <-
               Accounts.register_verified(
                 did,
                 verified.wallet_address,
                 verified.wallet_addresses,
                 actor: actor
               ) do
          refresh_if_evidence(account, verified, actor)
        end

      {:ok, account} ->
        Accounts.refresh_verified(
          account,
          verified.wallet_address,
          verified.wallet_addresses,
          actor: actor
        )

      error ->
        error
    end
  end

  def establish(_verified), do: {:error, :invalid_verified_identity}

  defp refresh_if_evidence(account, %{wallet_addresses: [_ | _]} = verified, actor) do
    Accounts.refresh_verified(
      account,
      verified.wallet_address,
      verified.wallet_addresses,
      actor: actor
    )
  end

  defp refresh_if_evidence(account, _verified, _actor), do: {:ok, account}
end
