defmodule Regents.Autolaunch.HomeMarket do
  @moduledoc """
  The reading behind the website's lists and the public JSON API: one page of
  auctions or tokens, the connected accounts of their creators, and the few
  auctions the home page shows beside its list. The
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
  The first `limit` auctions of the lists in the order `arguments` name (the
  `state` and `sort` of Auction's `:home_market`), for the rows beside the
  home page's list: Bid volume and Coming next. Unlike `read/3` it reads no
  creator's links, no FDV and no cursor, since those rows show none of them.
  """
  @spec auctions(map(), pos_integer()) :: {:ok, [Ash.Resource.record()]} | {:error, term()}
  def auctions(arguments, limit) do
    query =
      Ash.Query.for_read(Auction, :home_market, Map.put(arguments, :view, "new"), actor: nil)

    with {:ok, page} <- Ash.read(query, page: [limit: limit]), do: {:ok, page.results}
  end

  @public_link_providers [:x, :ens, :github]

  @doc """
  The connected accounts of the creators of one page's records (`read/3`'s
  results), by account id: their verified X profile and company
  (`XConnection`, as `:profile` and `:company`) and their linked X, ENS and
  GitHub accounts (as `:x`, `:ens` and `:github`), each with its `username`.
  Records that already carry loaded `creator_links` use them directly; records
  without `creator_links` (such as Create page previews or Robinhood pages)
  batch-read `Regents.Account.Accounts.public_links_for_accounts/1`.
  The X read asks for one page's creators only, so it is capped at the
  page's size.
  """
  @spec creators([map()]) :: {:ok, %{integer() => map()}} | {:error, term()}
  def creators(records) do
    creators =
      records
      |> Enum.map(&creator_record/1)
      |> Enum.filter(&match?(%{creator_human_account_id: id} when is_integer(id), &1))

    ids = creators |> Enum.map(& &1.creator_human_account_id) |> Enum.uniq()

    with {:ok, connections} <- x_connections(ids),
         {:ok, linked} <- linked_by_creator(creators) do
      {:ok,
       Enum.reduce(connections, linked, fn connection, grouped ->
         Map.update(
           grouped,
           connection.human_account_id,
           %{connection.role => connection},
           &Map.put(&1, connection.role, connection)
         )
       end)}
    end
  end

  # A page with no signed-up creator asks nothing, as autolaunch.sh's did.
  defp x_connections([]), do: {:ok, []}

  defp x_connections(ids) do
    case XConnection
         |> Ash.Query.for_read(:public_for_humans, %{human_account_ids: ids}, actor: nil)
         |> Ash.read() do
      {:ok, connections} ->
        {:ok, connections}

      {:error, error} ->
        if undefined_table?(error), do: {:ok, []}, else: {:error, error}
    end
  end

  defp undefined_table?(%{errors: errors}) when is_list(errors),
    do: Enum.any?(errors, &undefined_table?/1)

  defp undefined_table?(%{error: inner}), do: undefined_table?(inner)
  defp undefined_table?(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: true

  defp undefined_table?(message) when is_binary(message),
    do: String.contains?(message, "ERROR 42P01 (undefined_table)")

  defp undefined_table?(_other), do: false

  defp creator_record(%Token{auction: auction}), do: auction
  defp creator_record(%Auction{} = auction), do: auction
  defp creator_record(%{creator_human_account_id: _} = record), do: record
  defp creator_record(_other), do: nil

  defp linked_by_creator(creators) do
    {preloaded, missing_ids} =
      Enum.reduce(creators, {%{}, MapSet.new()}, &collect_creator_links/2)

    case MapSet.to_list(missing_ids) do
      [] -> {:ok, preloaded}
      ids -> fetch_public_links(ids, preloaded)
    end
  end

  defp collect_creator_links(record, {acc, missing}) do
    id = record.creator_human_account_id

    case Map.get(record, :creator_links) do
      %{} = links when not is_struct(links) ->
        {Map.put(acc, id, linked(links)), MapSet.delete(missing, id)}

      _unloaded ->
        mark_missing_creator_links(acc, missing, id)
    end
  end

  defp mark_missing_creator_links(acc, missing, id) do
    if Map.has_key?(acc, id),
      do: {acc, missing},
      else: {Map.put(acc, id, %{}), MapSet.put(missing, id)}
  end

  defp fetch_public_links(ids, grouped) do
    if Regents.read_only?() do
      {:ok, grouped}
    else
      ids
      |> Enum.chunk_every(100)
      |> Enum.reduce_while({:ok, grouped}, &fetch_public_links_batch/2)
    end
  end

  defp fetch_public_links_batch(batch, {:ok, acc}) do
    case Regents.Account.Accounts.public_links_for_accounts(batch) do
      {:ok, links} -> {:cont, {:ok, merge_public_links(acc, links)}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp merge_public_links(grouped, links) do
    Enum.reduce(links, grouped, fn link, acc ->
      if link.provider in @public_link_providers and is_binary(link.username) and
           link.username != "" do
        Map.update(
          acc,
          link.human_account_id,
          %{link.provider => %{username: link.username}},
          &Map.put(&1, link.provider, %{username: link.username})
        )
      else
        acc
      end
    end)
  end

  defp linked(links),
    do:
      for(
        {provider, name} <- links,
        is_binary(name) and name != "",
        into: %{},
        do: {provider, %{username: name}}
      )
end
