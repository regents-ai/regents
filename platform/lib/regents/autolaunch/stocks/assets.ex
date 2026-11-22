defmodule Regents.Autolaunch.Stocks.Assets do
  @moduledoc """
  The stock currencies of Base, answered from the saved stocks
  (`Regents.Autolaunch.Stocks.Stock`). A stock the launchpad revokes still
  answers here, so auctions already trading in it keep their dollar figures.

  Base's stocks are read from the database at most once a minute on each
  server and kept in between (`Regents.Autolaunch.Stocks.ListCache`); a failed
  read is not kept. Base is empty when its Stocks deployment description is not
  configured. Base stocks are saved under Base's own chain id whichever chain
  the Base description runs on, since a local fork carries the same tokens at
  the same addresses.

  Robinhood's stocks come with Robinhood's dollar prices.
  """

  alias Regents.Autolaunch.Stocks.{Lab, ListCache, Stock}

  @base_chain_id 8453

  @doc """
  The stocks Base's launchpad admits now or once admitted, by ticker, or the
  failed read's error.
  """
  @spec known(:base) :: {:ok, [Stock.t()]} | {:error, term()}
  def known(:base), do: if(Lab.configured?(), do: saved(@base_chain_id), else: {:ok, []})

  @doc """
  The exchange ticker behind a stock token symbol: the symbol without the Base
  issuer's trailing `c`, so `AAPLc` and Robinhood's `AAPL` are the same company.
  """
  def ticker(symbol) when is_binary(symbol), do: String.replace_suffix(symbol, "c", "")

  defp saved(chain_id),
    do: ListCache.stocks(chain_id, fn -> Regents.Autolaunch.launch_currency_stocks(chain_id) end)
end
