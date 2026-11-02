defmodule Regents.Points.Accounts do
  @moduledoc """
  What Regent Points asks this site about its accounts: the wallets an
  account's sign-in verified and the names of an account's own paired agents.
  """

  @behaviour RegentPoints.Accounts

  alias Regents.Accounts
  alias Regents.Actors.System

  @impl true
  def human(id), do: Accounts.points_account!(id, actor: %System{})

  @impl true
  def agent_names(_id, []), do: {:ok, %{}}

  def agent_names(id, wallets) do
    # The canonical account supplies the owner; a wallet's newest pairing names it.
    with {:ok, account} <- Accounts.points_account(id, actor: %System{}),
         {:ok, pairings} <- RegentAgents.pairing_histories(account.privy_user_id) do
      names = for %{wallet: wallet, name: name} <- pairings, wallet in wallets, do: {wallet, name}
      {:ok, Map.new(names)}
    end
  end
end
