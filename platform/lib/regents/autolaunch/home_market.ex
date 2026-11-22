defmodule Regents.Autolaunch.HomeMarket do
  @moduledoc """
  The reading behind the website's lists and the public JSON API: one page of
  auctions or tokens, and the connected accounts of their creators. The
  options, the addresses and the signed cursors are the web side's
  (`RegentsWeb.Autolaunch.HomeMarket`).
  """
  alias Regents.Autolaunch.{Auction, Token, XConnection}

  @doc """
  One page of a list. `options` are the list's options as
  `RegentsWeb.Autolaunch.HomeMarket.options/1` gives them, `page` Ash's page
  options (`[limit: n]`, or `[limit: n, after: keyset]` for a later page) and
  `unshown` the auction fields left out. Answers the page and whether it holds
  auctions or tokens. Every auction, and every token's auction, carries its
  creator's linked usernames (`creator_links`) for `creators/1`, and every
  token has its auction.
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
         |> Ash.Query.load([:market_cap, auction: [:creator_links]]), :token}
      else
        {Auction
         |> Ash.Query.for_read(
           :home_market,
           Map.merge(arguments, %{view: "new", state: options.state, sort: options.sort}),
           actor: nil
         )
         |> Ash.Query.load([:fdv, :creator_links])
         |> Ash.Query.deselect(unshown), :auction}
      end

    with {:ok, page} <- Ash.read(query, page: page),
         {:ok, page} <- shown(page),
         do: {:ok, page, kind}
  end

  # A token's auction is read by a second statement. A token whose auction
  # left the lists between the two is not shown. A page that loses every token
  # that way has no last record to continue from, so it is an error and the
  # next read asks again.
  defp shown(%{results: results} = page) do
    case Enum.reject(results, &match?(%Token{auction: nil}, &1)) do
      [] when results != [] -> {:error, :changed_while_read}
      kept -> {:ok, %{page | results: kept}}
    end
  end

  @doc """
  The connected accounts of the creators of one page's records (`read/3`'s
  results), by account id: their verified X profile and company
  (`XConnection`, as `:profile` and `:company`) and their linked X, ENS and
  GitHub accounts (as `:x`, `:ens` and `:github`), each with its `username`.
  The X read asks for one page's creators only, so it is capped at the
  page's size.
  """
  @spec creators([struct()]) :: {:ok, %{integer() => map()}} | {:error, term()}
  def creators(records) do
    auctions =
      records |> Enum.map(&auction/1) |> Enum.filter(&is_integer(&1.creator_human_account_id))

    ids = auctions |> Enum.map(& &1.creator_human_account_id) |> Enum.uniq()

    with {:ok, connections} <- x_connections(ids) do
      linked = Map.new(auctions, &{&1.creator_human_account_id, linked(&1.creator_links)})

      {:ok,
       Enum.reduce(connections, linked, fn connection, grouped ->
         Map.update!(
           grouped,
           connection.human_account_id,
           &Map.put(&1, connection.role, connection)
         )
       end)}
    end
  end

  # A page with no signed-up creator asks nothing, as autolaunch.sh's did.
  defp x_connections([]), do: {:ok, []}

  defp x_connections(ids),
    do:
      XConnection
      |> Ash.Query.for_read(:public_for_humans, %{human_account_ids: ids}, actor: nil)
      |> Ash.read()

  defp auction(%Token{auction: auction}), do: auction
  defp auction(%Auction{} = auction), do: auction

  defp linked(links),
    do:
      for(
        {provider, name} <- links,
        is_binary(name),
        into: %{},
        do: {provider, %{username: name}}
      )
end
