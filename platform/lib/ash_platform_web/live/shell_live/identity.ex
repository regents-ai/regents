defmodule AshPlatformWeb.ShellLive.Identity do
  @moduledoc """
  Who the shell's pages act for. The session hook keeps `access_context` current
  on every navigation and event; each feature reads the account and its wallets
  from here rather than keeping its own copy.
  """

  alias AshPlatform.Actors.Human

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

  @doc "The signed-in account's wallets, the only ones that may act; `nil` signed out."
  def linked_wallets(access_context) do
    case current_account(access_context) do
      nil -> nil
      account -> account_wallets(account)
    end
  end

  @doc """
  Privy's active wallet is the only wallet that acts. Signed in, Stake and
  Redeem show it when it is one of the account's own wallets; any other wallet
  is one to switch away from, so the page stays on the account's first wallet
  and asks. Signed out, the page shows whatever wallet is active.
  """
  def position_wallet(%{access_context: access_context, browser_wallet: browser_wallet}) do
    case current_account(access_context) do
      nil ->
        browser_wallet

      account ->
        wallets = account_wallets(account)
        if browser_wallet in wallets, do: browser_wallet, else: List.first(wallets)
    end
  end
end
