defmodule Regents.Autolaunch.Token.Preparations.BaseAuctionOnly do
  @moduledoc false
  use Ash.Resource.Preparation

  # A token whose auction is a listed Base auction: one created through this
  # site, or a Memestock launch sent anywhere. `path` leads from what is read
  # to that auction: a token's own (`[:auction]`, as the token's reads have
  # it) or a revenue row's token's (`[:token, :auction]`). The public lists,
  # which also carry Robinhood tokens, use
  # `Regents.Autolaunch.Token.Preparations.ListedAuction`.
  @impl true
  def prepare(query, opts, _context),
    do:
      base(
        query,
        Keyword.get(opts, :path, [:auction]),
        Regents.Autolaunch.Robinhood.Lab.chain_id(),
        Regents.Autolaunch.Stocks.Lab.chain_id()
      )

  defp base(query, path, nil, nil),
    do: Ash.Query.filter(query, exists(^path, origin == :site))

  defp base(query, path, robinhood, nil),
    do: Ash.Query.filter(query, exists(^path, origin == :site and chain_id != ^robinhood))

  defp base(query, path, nil, base),
    do:
      Ash.Query.filter(
        query,
        exists(
          ^path,
          origin == :site or (origin == :chain and kind == :stocks and chain_id == ^base)
        )
      )

  defp base(query, path, robinhood, base),
    do:
      Ash.Query.filter(
        query,
        exists(
          ^path,
          (origin == :site and chain_id != ^robinhood) or
            (origin == :chain and kind == :stocks and chain_id == ^base)
        )
      )
end
