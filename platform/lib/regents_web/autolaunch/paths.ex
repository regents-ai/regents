defmodule RegentsWeb.Autolaunch.Paths do
  @moduledoc """
  Where every auction's and token's page lives, on both chains:
  `/autolaunch/auctions/<TICKER>/<tail>` and `/autolaunch/tokens/<TICKER>/<tail>`,
  where the ticker keeps the case it was launched with and the tail is the end
  of the auction's contract address (`Regents.Autolaunch.Auction`'s
  `path_tail`, five characters unless another auction with the same ticker
  shares them). A token carries its auction's tail, so the two pages pair up.

  Every page function takes the auction, loaded with `path_tail`; a token's
  page is named by the auction it launched from. Those pages are not here yet,
  so the addresses are written out rather than checked against the router, and
  answer 404 until their pages come.

  Also where a page shows a launch's picture: a stored one
  (`Regents.Autolaunch.StoredImage`) from this site, at
  `/autolaunch/images/<id>/<digest>/<width>.webp` or
  `/autolaunch/stock-images/...`, whatever host its record names.
  """

  use RegentsWeb, :verified_routes

  alias Regents.Autolaunch.StoredImage

  @choices [320, 640]

  @doc "The auction's page."
  def auction(auction), do: "/autolaunch/auctions/#{symbol(auction)}/#{auction.path_tail}"

  @doc "The page of the token the auction launched."
  def token(auction), do: "/autolaunch/tokens/#{symbol(auction)}/#{auction.path_tail}"

  @doc """
  Where a page shows the image at `url` at `width` (96, 320 or 640): a stored
  image's sized copy on this site, and any other `https` address with a host,
  such as one on another site, as it is. Nil for a launch with no image and
  for any other address, where the page shows the name's first letter.
  """
  @spec sized(String.t() | nil, StoredImage.width()) :: String.t() | nil
  def sized(nil, _width), do: nil

  def sized(url, width) do
    case StoredImage.key(url) do
      {:ok, key} -> copy(key, width)
      :error -> drawn(url)
    end
  end

  @doc """
  The widths a large picture's browser chooses from, as an `<img>`'s
  `srcset`, beside `sized(url, 640)` as its `src`; nil for an address that is
  not a stored image.
  """
  @spec choices(String.t() | nil) :: String.t() | nil
  def choices(nil), do: nil

  def choices(url) do
    case StoredImage.key(url) do
      {:ok, key} -> Enum.map_join(@choices, ", ", &"#{copy(key, &1)} #{&1}w")
      :error -> nil
    end
  end

  defp copy({"images", id, digest}, width),
    do: ~p"/autolaunch/images/#{id}/#{digest}/#{"#{width}.webp"}"

  defp copy({"stock-images", id, digest}, width),
    do: ~p"/autolaunch/stock-images/#{id}/#{digest}/#{"#{width}.webp"}"

  # An address that is not a stored image is drawn only when it is `https`,
  # with a host.
  defp drawn(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" -> url
      _other -> nil
    end
  end

  # A ticker is one path segment, encoded as the router's own addresses are.
  defp symbol(%{token_symbol: symbol}) when is_binary(symbol),
    do: URI.encode(symbol, &URI.char_unreserved?/1)
end
