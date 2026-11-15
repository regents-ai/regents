defmodule RegentsWeb.ShellLive.Identity do
  @moduledoc """
  Who the shell's pages act for. The session hook keeps `access_context` current
  on every navigation and event; each feature reads the account and its wallets
  from here rather than keeping its own copy.
  """

  alias Regents.Actors.Human

  def current_account(%{principal: {:human, account}}), do: account
  def current_account(_access_context), do: nil

  def authenticated?(access_context), do: not is_nil(current_account(access_context))

  def human_actor(%{assigns: %{access_context: access_context}}) do
    case current_account(access_context) do
      nil -> nil
      account -> %Human{human_account_id: account.id, wallet_addresses: account_wallets(account)}
    end
  end

  def account_wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  @doc """
  The signed-in account's main wallet, lowercased: the one its menu shows and
  the only one Stake and Redeem act for. `nil` signed out.
  """
  def main_wallet(nil), do: nil
  def main_wallet(account), do: String.downcase(account.wallet_address)

  @doc """
  The wallet Stake and Redeem show. Signed in, the account's main wallet,
  whichever wallet the browser has open. Signed out, the wallet the browser has
  open.
  """
  def position_wallet(%{access_context: access_context, browser_wallet: browser_wallet}) do
    case current_account(access_context) do
      nil -> browser_wallet
      account -> main_wallet(account)
    end
  end
end
