defmodule Regents.Autolaunch.HomeMarket do
  @moduledoc """
  The reading behind the website's lists and the public JSON API: one page of
  auctions or tokens. The options, the addresses and the signed cursors are the
  web side's (`RegentsWeb.Autolaunch.HomeMarket`).
  """
  alias Regents.Autolaunch.{Auction, Token}

  @doc """
  One page of a list. `options` are the list's options as
  `RegentsWeb.Autolaunch.HomeMarket.options/1` gives them, `page` Ash's page
  options (`[limit: n]`, or `[limit: n, after: keyset]` for a later page) and
  `unshown` the auction fields left out. Answers the page and whether it holds
  auctions or tokens.
  """
  @spec read(map(), keyword(), [atom()]) ::
          {:ok, Ash.Page.Keyset.t(), :auction | :token} | {:error, term()}
  def read(options, page, unshown) do
    arguments = %{
      query: options.q,
      chain: options.chain,
      kind: options.kind,
      x: options.x,
      ens: options.ens,
      github: options.github
    }

    {query, kind} =
      if options.view == "tokens" do
        {Token
         |> Ash.Query.for_read(:home_market, arguments, actor: nil)
         |> Ash.Query.load(:market_cap), :token}
      else
        {Auction
         |> Ash.Query.for_read(
           :home_market,
           Map.merge(arguments, %{view: "new", state: options.state, sort: options.sort}),
           actor: nil
         )
         |> Ash.Query.load(:fdv)
         |> Ash.Query.deselect(unshown), :auction}
      end

    with {:ok, page} <- Ash.read(query, page: page), do: {:ok, page, kind}
  end
end
