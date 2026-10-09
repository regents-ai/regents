defmodule Regents.Actors.Agent do
  @moduledoc "A SIWA agent acting for its current paired owner, never as a human."
  @enforce_keys [:wallet_address, :pairing_id, :privy_user_id, :human_account_id]
  defstruct [
    :wallet_address,
    :pairing_id,
    :privy_user_id,
    :human_account_id,
    :beneficiary_wallet_address,
    wallet_addresses: [],
    role: :agent
  ]

  def paired(wallet, pairing, account) do
    wallets = [account.wallet_address | account.wallet_addresses || []]

    %__MODULE__{
      wallet_address: wallet,
      pairing_id: pairing.id,
      privy_user_id: pairing.privy_user_id,
      human_account_id: account.id,
      beneficiary_wallet_address: normalize(account.wallet_address),
      wallet_addresses: wallets |> Enum.map(&normalize/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    }
  end

  defp normalize(wallet) when is_binary(wallet) do
    wallet = String.downcase(wallet)
    if Regex.match?(~r/\A0x[0-9a-f]{40}\z/, wallet), do: wallet
  end

  defp normalize(_), do: nil
end
