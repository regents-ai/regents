defmodule Regents.Autolaunch.LinkedCreators do
  @moduledoc """
  Which creators of the listed launches hold a linked account of each provider
  a list read filters by, for the lists' X, ENS and GitHub filters
  (`:home_market` on `Regents.Autolaunch.Auction` and
  `Regents.Autolaunch.Token`). A list read asks once, for every filter it has
  on, and not at all when none is on.

  The creators are those of the auctions the lists may show (`Auction`'s
  `:listed_shown`, the lists' own listing rule; a token is listed only with
  its auction); a launch with no creator is left out. Their links are
  regents.sh's, read through the Account read
  (`Regents.Account.Accounts.list_linked_identities_for_accounts!/2`), at most
  100 accounts a read. As on autolaunch.sh, a link counts when it names a
  username; when Privy last checked it is not asked.

  On the read-only venue (`Regents.read_only?/0`) the site's database login
  cannot read linked accounts, so there no creator holds one and nothing is
  read: the X filter rests on X connections alone, and the ENS and GitHub
  filters find nothing. This is the one place the lists ask which venue this is.
  """

  alias Regents.Account.Accounts
  alias Regents.Account.Actors.System
  alias Regents.Autolaunch.Auction

  @type provider :: :x | :ens | :github

  # The most accounts the Account read takes at once.
  @accounts_a_read 100

  @doc """
  For each provider asked for, the account ids of the listed launches'
  creators that hold a link of it. Nothing is read when none is asked for.
  """
  @spec holding!([provider()]) :: %{optional(provider()) => [integer()]}
  def holding!([]), do: %{}

  def holding!(providers) do
    links = if Regents.read_only?(), do: [], else: links()

    Map.new(providers, fn provider ->
      ids =
        for %{provider: ^provider, username: username, human_account_id: id} <- links,
            not is_nil(username),
            do: id

      {provider, ids}
    end)
  end

  defp links do
    Auction
    |> Ash.Query.for_read(:listed_shown, %{}, actor: nil)
    # A launch with no creator (a Robinhood launch may have none) stays out of the query.
    |> Ash.list!(:creator_human_account_id, uniq?: true, include_nil?: false)
    |> Enum.chunk_every(@accounts_a_read)
    |> Enum.flat_map(&Accounts.list_linked_identities_for_accounts!(&1, actor: %System{}))
  end
end
