defmodule RegentsWeb.Autolaunch.Paths do
  @moduledoc """
  Where every auction's and token's page lives, on both chains:
  `/autolaunch/auctions/<TICKER>/<tail>` and `/autolaunch/tokens/<TICKER>/<tail>`,
  where the ticker keeps the case it was launched with and the tail is the end
  of the auction's contract address (`Regents.Autolaunch.Auction`'s
  `path_tail`, five characters unless another auction with the same ticker
  shares them). A token carries its auction's tail, so the two pages pair up.

  Every function takes the auction, loaded with `path_tail`; a token's page is
  named by the auction it launched from. Those pages are not here yet, so the
  addresses are written out rather than checked against the router, and answer
  404 until their pages come.
  """

  @doc "The auction's page."
  def auction(auction), do: "/autolaunch/auctions/#{symbol(auction)}/#{auction.path_tail}"

  @doc "The page of the token the auction launched."
  def token(auction), do: "/autolaunch/tokens/#{symbol(auction)}/#{auction.path_tail}"

  # A ticker is one path segment, encoded as the router's own addresses are.
  defp symbol(%{token_symbol: symbol}) when is_binary(symbol),
    do: URI.encode(symbol, &URI.char_unreserved?/1)
end
