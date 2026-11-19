defmodule RegentPoints.Leaderboard do
  @moduledoc """
  The board every reader of a site's Points page shares, read once for all of them
  under the system actor: the ten highest totals by public name. Highest total
  first, then the lowest account id, so the order inside a tie is the same on every
  read. It reads those ten accounts' stored totals from one index
  (`RegentPoints.Account`), never every account.

  A row's place is one more than the number of accounts with strictly more
  points, so accounts level on points share a place. Every account above a listed
  row is listed too, so the ten rows give their own places. A reader's place
  wherever they sit comes with their own summary (`RegentPoints.Summary`).

  Each row carries its account id so the site can mark the reader's own row. The
  site keeps the ids on the server: a page or an agent gets the rows' names or
  wallets, pictures, places and totals.
  """
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Store}

  @size 10

  @impl true
  def run(_input, _, _context) do
    query =
      Account
      |> Ash.Query.filter(balance_micro > 0)
      |> Ash.Query.select([:balance_micro])
      |> Ash.Query.sort(balance_micro: :desc, id: :asc)
      |> Ash.Query.limit(@size)

    with {:ok, top} <- Points.read_accounts(query: query, actor: Store.system()),
         {:ok, people} <- RegentPoints.accounts().people(Enum.map(top, & &1.id)) do
      totals = Enum.map(top, & &1.balance_micro)
      {:ok, %{top: Enum.map(top, &row(&1, totals, people))}}
    end
  end

  defp row(account, totals, people) do
    people
    |> Map.fetch!(account.id)
    |> Map.take([:name, :wallet, :ens_name, :squares, :picture])
    |> Map.merge(%{
      account_id: account.id,
      rank: Enum.count(totals, &(&1 > account.balance_micro)) + 1,
      points_micro: account.balance_micro
    })
  end
end
