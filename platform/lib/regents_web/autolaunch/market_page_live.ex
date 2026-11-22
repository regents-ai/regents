defmodule RegentsWeb.Autolaunch.MarketPageLive do
  @moduledoc """
  A launched Base token's page at `/autolaunch/tokens/<TICKER>/<tail>` (see
  `RegentsWeb.Autolaunch.Paths`), which `RegentsWeb.Autolaunch.TokenLive`
  shows and is handed every callback.

  The first render, the one link previews read, finds the token the address
  names (`Regents.Autolaunch.TokenPage.find/3`) and gives the page its title
  and description; the share picture is the site's own, as on Autolaunch's
  other pages. An address that names nothing, a Robinhood market, or an
  auction whose token has not launched is the site's not-found page, and a
  read that fails is the site's error page. The open page reads the token
  again itself, under the address's allowance, and names the tab where that
  answer lands (`handle_async/3`), which a page opened from a Tokens row or a
  Buy, having no first render, needs.

  Still to come: an auction's page, and Robinhood's own pages.
  """
  use RegentsWeb, :live_view

  alias RegentsWeb.Autolaunch.{PublicDocuments, TokenLive}

  def mount(%{"symbol" => symbol, "tail" => tail} = params, session, socket) do
    socket = if connected?(socket), do: socket, else: assign(socket, document(symbol, tail))
    TokenLive.mount(params, session, socket)
  end

  def handle_event(event, params, socket), do: TokenLive.handle_event(event, params, socket)

  def handle_async(name, answer, socket), do: TokenLive.handle_async(name, answer, socket)

  def render(assigns), do: TokenLive.render(assigns)

  defp document(symbol, tail) do
    case Regents.Autolaunch.TokenPage.find(symbol, tail) do
      {:ok, auction, _token} ->
        PublicDocuments.market_page(:token, auction.title, auction.token_symbol)

      :error ->
        raise RegentsWeb.NotFoundError

      {:error, error} ->
        raise error
    end
  end
end
