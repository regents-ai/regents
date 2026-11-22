defmodule Regents.Autolaunch.TokenPage do
  @moduledoc """
  The reads behind a launched token's own page, which its address names: the
  ticker, in any case, and the end of its auction's contract address
  (`Regents.Autolaunch.Auction`'s `:by_path`), found as autolaunch.sh's
  `AutolaunchWeb.Paths.find_token/2` found it. Only a Base token has a page
  here, so a Robinhood market's address names none.

  A ticker that is not valid UTF-8 names nothing, and one over 16 characters,
  or a tail that is not 5 to 40 hex digits, is refused by the read's own
  arguments; neither makes a statement.
  """

  alias Regents.Autolaunch.{HomeMarket, Pool, PoolCache, Token}
  alias Regents.Autolaunch.Robinhood.Lab, as: RobinhoodLab

  @doc """
  The listed auction the address's `symbol` and `tail` name, with `path_tail`,
  and the token it launched, with `load` loaded on it. `:error` when the
  address names no listed auction, is too short to name only one, cannot name
  one, or names a Robinhood market or an auction whose token has not launched;
  `{:error, error}` when a read fails.
  """
  @spec find(String.t(), String.t(), list()) ::
          {:ok, struct(), Token.t()} | :error | {:error, term()}
  def find(symbol, tail, load \\ []) do
    if String.valid?(symbol) do
      case Regents.Autolaunch.list_auctions_by_path(symbol, tail, actor: nil) do
        {:ok, [auction]} -> launched(auction, load)
        {:ok, _none_or_several} -> :error
        {:error, %Ash.Error.Invalid{}} -> :error
        {:error, error} -> {:error, error}
      end
    else
      :error
    end
  end

  @doc """
  What the page shows of the token the address names: the token with its
  `market_cap` and its auction, with the auction's `creator_links`, and the
  connected accounts of its creator by account id
  (`Regents.Autolaunch.HomeMarket.creators/1`). `{:ok, nil}` when the address
  names no launched token any more; a failed read, the accounts' included, is
  `{:error, error}`.
  """
  @spec read(String.t(), String.t()) ::
          {:ok, %{token: Token.t(), creators: map()} | nil} | {:error, term()}
  def read(symbol, tail) do
    with {:ok, _auction, token} <- find(symbol, tail, [:market_cap, auction: [:creator_links]]),
         {:ok, creators} <- HomeMarket.creators([token]) do
      {:ok, %{token: token, creators: creators}}
    else
      :error -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The revenue recorded for the token the address names, newest first, at most
  the latest fifty (`Regents.Autolaunch.TokenRevenue`'s `:for_token`);
  `{:error, :not_found}` when the address names no launched token any more.
  """
  @spec revenue(String.t(), String.t()) :: {:ok, [struct()]} | {:error, term()}
  def revenue(symbol, tail) do
    case find(symbol, tail) do
      {:ok, _auction, token} -> Regents.Autolaunch.token_revenue(token.id, actor: nil)
      :error -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The pool of the token the address names, as the chain gave it within the
  last 15 seconds (`Regents.Autolaunch.PoolCache.pool/2`), or read from it now
  (`Regents.Autolaunch.Pool.read/1`); `{:error, :not_graduated}` when the
  address names no launched token any more.
  """
  @spec pool(String.t(), String.t()) :: {:ok, Pool.t()} | {:error, term()}
  def pool(symbol, tail) do
    case find(symbol, tail) do
      {:ok, auction, _token} -> PoolCache.pool(auction.id, fn -> Pool.read(auction) end)
      :error -> {:error, :not_graduated}
      {:error, error} -> {:error, error}
    end
  end

  defp launched(auction, load) do
    if RobinhoodLab.chain?(auction.chain_id) do
      :error
    else
      case Regents.Autolaunch.get_public_token_by_auction(auction.id, actor: nil, load: load) do
        {:ok, %Token{} = token} -> {:ok, auction, token}
        {:ok, nil} -> :error
        {:error, error} -> {:error, error}
      end
    end
  end
end
