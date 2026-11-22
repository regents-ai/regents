defmodule Regents.Autolaunch.Token.Preparations.ShownAuction do
  @moduledoc false
  use Ash.Resource.Preparation

  # A token is shown when its auction is: see
  # `Regents.Autolaunch.Auction.Preparations.Shown`. `path` leads from what is
  # read to that auction, as in
  # `Regents.Autolaunch.Token.Preparations.BaseAuctionOnly`.
  @impl true
  def prepare(query, opts, _context) do
    path = Keyword.get(opts, :path, [:auction])
    Ash.Query.filter(query, exists(^path, not hidden))
  end
end
