defmodule RegentsWeb.Autolaunch.Search do
  @moduledoc "Public auction and token results for workspace search."

  alias Regents.Autolaunch.{Prelaunch, Token}
  alias RegentsWeb.Autolaunch.{HomeMarket, Paths}

  @doc "Reads a small page of public matches for each market list."
  def matches(query) do
    if Prelaunch.read_only?() do
      {:ok, []}
    else
      with {:ok, auctions} <- records("auctions", query, &auction/1),
           {:ok, tokens} <- records("tokens", query, &token/1) do
        {:ok, auctions ++ tokens}
      end
    end
  end

  defp records(view, query, to_item) do
    options = HomeMarket.options(%{"view" => view, "q" => query})

    with {:ok, page} <- HomeMarket.read(options, nil, 4) do
      results = Enum.map(page.records, to_item)

      if page.has_more do
        path = HomeMarket.path(options, %{}, "/autolaunch/#{view}")

        {:ok,
         results ++ [%{item("All matching " <> view, path, "Autolaunch", nil) | fallback: 4}]}
      else
        {:ok, results}
      end
    end
  end

  defp auction(auction),
    do: item(auction.title, Paths.auction(auction), "Auction", auction.token_symbol)

  defp token(token) do
    %{name: name, symbol: symbol} = Token.presentation(token)
    item(name, Paths.token(token.auction), "Token", symbol)
  end

  defp item(label, path, kind, symbol) do
    %{
      kind: :market,
      label: label,
      path: path,
      detail: Enum.join(Enum.reject([kind, symbol], &is_nil/1), " · "),
      product: "autolaunch",
      fallback: 7
    }
  end
end
