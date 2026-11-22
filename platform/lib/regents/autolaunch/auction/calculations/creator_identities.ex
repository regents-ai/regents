defmodule Regents.Autolaunch.Auction.Calculations.CreatorIdentities do
  @moduledoc """
  What the lists read of an auction creator's linked accounts, inside the
  list's own query: regents.sh's verified links that name a username
  (`creator_identities`, over `Regents.Account.Accounts.PublicLink`). With
  `answer: :linked`, whether the creator holds one of the calculation's
  `provider` (the X, ENS and GitHub filters); with `answer: :names`, the
  usernames and then the display names of their X, GitHub and ENS links
  (`creator_identity_names` and `creator_identity_display_names`, for the
  search's `search_rank`).

  The read-only venue's database login is not granted those links, so there
  the expression names none of them: no creator holds one and there are no
  names. The venue is set as the site starts (`Regents.read_only?/0`), so a
  running site builds the same expression for every query. This is the one
  place the lists ask which venue this is, and the only one that reads
  `creator_identities` or its two aggregates.
  """
  use Ash.Resource.Calculation

  @impl true
  def expression(opts, _context), do: answer(opts[:answer], Regents.read_only?())

  defp answer(:linked, true), do: expr(false)
  defp answer(:linked, false), do: expr(exists(creator_identities, provider == ^arg(:provider)))
  defp answer(:names, true), do: expr(type([], {:array, :string}))

  defp answer(:names, false),
    do: expr(fragment("? || ?", creator_identity_names, creator_identity_display_names))
end
