defmodule RegentsWeb.Account.Identity do
  @moduledoc """
  Who the shell's pages act for. The session hook keeps `access_context` current
  on every navigation and event; each feature reads the account and its wallets
  from here rather than keeping its own copy.
  """

  alias Regents.Account.Actors.Human

  def current_account(%{principal: {:human, account}}), do: account
  def current_account(_access_context), do: nil

  def authenticated?(access_context), do: not is_nil(current_account(access_context))

  def human_actor(%{assigns: %{access_context: access_context}}) do
    case current_account(access_context) do
      nil -> nil
      account -> Human.for_account(account)
    end
  end

  @doc """
  The signed-in account's main wallet, lowercased. `nil` signed out.
  """
  def main_wallet(nil), do: nil
  def main_wallet(account), do: String.downcase(account.wallet_address)

  @doc """
  The signed-in account's active linked wallet, with its main wallet as fallback.
  Signed out, there is no signing wallet.
  """
  def signing_wallet(nil, _active), do: nil

  def signing_wallet(account, active) do
    if active in Human.for_account(account).wallet_addresses,
      do: active,
      else: main_wallet(account)
  end

  @doc """
  The wallet Stake and Redeem show. Signed in, it is the signing wallet.
  Signed out, the page can show the active wallet's public figures.
  """
  def position_wallet(%{access_context: access_context, browser_wallet: browser_wallet}) do
    case current_account(access_context) do
      nil -> browser_wallet
      account -> signing_wallet(account, browser_wallet)
    end
  end
end
