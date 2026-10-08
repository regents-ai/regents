defmodule Regents.Points.TrackWallets do
  @moduledoc """
  Reads an account's NFT holdings again on every sign-in, once NFT tracking is
  on, so an account whose wallets never change is still read. The job commits or
  rolls back with the account change, and a Points failure never fails the sign-in.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, account ->
      if RegentPoints.Nfts.tracking?() do
        RegentPoints.Enqueue.call(RegentPoints.RefreshHoldings, %{account_id: account.id})
      end

      {:ok, account}
    end)
  end
end
