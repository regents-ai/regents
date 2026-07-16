defmodule AshPlatform.Accounts.VerifiedSession do
  @moduledoc "Exchanges verified Privy evidence for the canonical human account."

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System

  def establish(%AshPlatform.VerifiedPrivyIdentity{privy_user_id: did} = verified)
      when is_binary(did) and did != "" do
    actor = %System{}

    case linked_wallet_evidence(verified) do
      {:ok, primary, addresses} ->
        with {:ok, account} <-
               Accounts.register_verified(did, primary, addresses, actor: actor) do
          Accounts.refresh_verified(account, primary, addresses, actor: actor)
        end

      {:error, :missing_linked_wallet} ->
        invalidate_wallet_evidence(did, actor)
    end
  end

  def establish(_verified), do: {:error, :invalid_verified_identity}

  def current?(%{wallet_address: primary, wallet_addresses: addresses})
      when is_binary(primary) and is_list(addresses) do
    addresses != [] and primary in addresses
  end

  def current?(_account), do: false

  defp linked_wallet_evidence(%{wallet_address: primary, wallet_addresses: addresses})
       when is_list(addresses) do
    addresses =
      addresses
      |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
      |> Enum.uniq()

    case addresses do
      [] ->
        {:error, :missing_linked_wallet}

      addresses ->
        primary = if primary in addresses, do: primary, else: hd(addresses)
        {:ok, primary, addresses}
    end
  end

  defp linked_wallet_evidence(_verified), do: {:error, :missing_linked_wallet}

  defp invalidate_wallet_evidence(did, actor) do
    with {:ok, account} when not is_nil(account) <-
           Accounts.get_by_privy_did(did, actor: actor),
         {:ok, _account} <- Accounts.refresh_verified(account, nil, [], actor: actor) do
      {:error, :missing_linked_wallet}
    else
      {:ok, nil} -> {:error, :missing_linked_wallet}
      error -> error
    end
  end
end
