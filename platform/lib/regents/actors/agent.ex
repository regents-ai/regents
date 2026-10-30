defmodule Regents.Actors.Agent do
  @moduledoc """
  A SIWA agent acting for its current paired owner, never as a human.

  `connection` is set when the agent is a connected app's own identity, acting
  through the hosted MCP server with the token its person approved: what
  `RegentOAuth.verify/3` answered for that token. The same app may then also run
  its identity tools (`Regents.Agents.Connection`).
  """
  @enforce_keys [:wallet_address, :pairing_id, :privy_user_id, :human_account_id]
  defstruct [
    :wallet_address,
    :pairing_id,
    :privy_user_id,
    :human_account_id,
    :beneficiary_wallet_address,
    :connection,
    wallet_addresses: [],
    role: :agent
  ]

  @type t :: %__MODULE__{}

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
