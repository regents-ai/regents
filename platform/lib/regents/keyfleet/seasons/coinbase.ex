defmodule Regents.Keyfleet.Seasons.Coinbase do
  @moduledoc """
  Coinbase's public market data, read with no account, key or secret: which
  products a season's picks may name, and a product's price at a boundary.

  A product may be picked when Coinbase's list of spot products
  (`GET /market/products`) shows it as spot, quoted in US dollars and open for
  trading (not disabled, trading not disabled, not view-only, not cancel-only,
  not limit-only, not in auction mode), with at least 1,000,000 US dollars
  traded over the last 24 hours (`approximate_quote_24h_volume`). `USDC`
  always may. A list that goes on past twenty pages is not read, nor one with a
  page that says more follow but names no next page (its cursor empty or
  missing).

  A product's price at boundary T is the newest good close among the
  one-minute candles of the season that ended at T
  (`GET /market/products/{product_id}/candles`, one request for every minute
  of the season, which Coinbase answers up to 350 at a time): the minute that
  started at T - 60 s, or, when that minute had no trade, the last that did.
  A close of 0 or below, or one that is not a number, is passed over for the
  minute before it, and with no good close all season there is no price.
  `USDC`'s price is 1.
  Prices are the decimals Coinbase sent.

  A product Coinbase no longer knows has no price. Any other answer but a
  reading is an error, and nothing is decided on it.

  The address comes from `config :regents, Regents.Keyfleet.Seasons.Coinbase, url:`.
  """

  alias Regents.Keyfleet.Seasons

  # The least a product must have traded over 24 hours, in US dollars, to be picked.
  @volume_floor Decimal.new(1_000_000)

  @usdc "USDC"

  # Every spot product quoted in US dollars is named this way on Coinbase.
  @usd_product ~r/\A[A-Z0-9]+-USD\z/

  # The most pages of the list one read follows. The list comes on one page
  # today; twenty leave room for it to come 100 products a page up to 2,000.
  @max_pages 20

  @doc "The least a product must have traded over 24 hours, in US dollars, to be picked."
  @spec volume_floor() :: Decimal.t()
  def volume_floor, do: @volume_floor

  @doc "The ids of every product that may be picked now, `USDC` among them."
  @spec eligible() :: {:ok, [String.t()]} | {:error, term()}
  def eligible do
    with {:ok, products} <- products(product_type: "SPOT"),
         do: {:ok, [@usdc | eligible_ids(products)]}
  end

  @doc """
  Which of `product_ids` may be picked now, kept from the whole list
  (`eligible/0`), which is not read when they name nothing but `USDC`.
  """
  @spec eligible_among([String.t()]) :: {:ok, MapSet.t(String.t())} | {:error, term()}
  def eligible_among(product_ids) do
    asked = MapSet.new(product_ids)

    if Enum.all?(asked, &(&1 == @usdc)) do
      {:ok, asked}
    else
      with {:ok, listed} <- eligible(),
           do: {:ok, MapSet.intersection(asked, MapSet.new(listed))}
    end
  end

  @doc "`product_id`'s price at `boundary`, or nil for none."
  @spec price(String.t(), DateTime.t()) :: {:ok, Decimal.t() | nil} | {:error, term()}
  def price(@usdc, _boundary), do: {:ok, Decimal.new(1)}

  def price(product_id, %DateTime{} = boundary) do
    first = boundary |> DateTime.add(-Seasons.season_hours(), :hour) |> DateTime.to_unix()
    last = DateTime.to_unix(boundary) - 60

    case get("/market/products/:product_id/candles",
           path_params: [product_id: product_id],
           params: [start: first, end: last, granularity: "ONE_MINUTE"]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"candles" => candles}}} ->
        {:ok, newest_close(candles, first..last//60)}

      {:ok,
       %Req.Response{
         status: 400,
         body: %{"error" => "INVALID_ARGUMENT", "error_details" => "valid product_id is required"}
       }} ->
        {:ok, nil}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:coinbase, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc false
  def eligible?(%{
        "product_id" => product_id,
        "product_type" => "SPOT",
        "quote_currency_id" => "USD",
        "is_disabled" => false,
        "trading_disabled" => false,
        "view_only" => false,
        "cancel_only" => false,
        "limit_only" => false,
        "auction_mode" => false,
        "approximate_quote_24h_volume" => volume
      })
      when is_binary(volume) do
    with true <- Regex.match?(@usd_product, product_id),
         {%Decimal{coef: coef} = volume, ""} when is_integer(coef) <- Decimal.parse(volume) do
      not Decimal.lt?(volume, @volume_floor)
    else
      _otherwise -> false
    end
  end

  def eligible?(_product), do: false

  defp eligible_ids(products),
    do: for(%{"product_id" => id} = product <- products, eligible?(product), do: id)

  # Every page of the list, following its cursor, up to `@max_pages`.
  defp products(params), do: products(params, @max_pages)

  defp products(_params, 0 = _pages_left), do: {:error, :too_many_pages}

  defp products(params, pages_left) do
    case get("/market/products", params: params) do
      {:ok, %Req.Response{status: 200, body: %{"products" => products} = body}} ->
        next_page(products, body["pagination"], params, pages_left - 1)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:coinbase, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp next_page(products, %{"has_next" => true, "next_cursor" => cursor}, params, pages_left)
       when is_binary(cursor) and cursor != "" do
    with {:ok, rest} <- products(Keyword.put(params, :cursor, cursor), pages_left),
         do: {:ok, products ++ rest}
  end

  defp next_page(_products, %{"has_next" => true}, _params, _pages_left),
    do: {:error, :no_next_cursor}

  defp next_page(products, _last_page, _params, _pages_left), do: {:ok, products}

  # The newest good close of the season's minutes, a bad one passed over.
  defp newest_close(candles, minutes) do
    candles
    |> Enum.map(fn %{"start" => start, "close" => close} ->
      {String.to_integer(start), above_zero(close)}
    end)
    |> Enum.filter(fn {start, price} -> start in minutes and price != nil end)
    |> Enum.max_by(fn {start, _price} -> start end, fn -> nil end)
    |> case do
      {_start, price} -> price
      nil -> nil
    end
  end

  # A close of 0 or below, or one that is not a number sent as text, is no price.
  defp above_zero(close) when is_binary(close) do
    case Decimal.parse(close) do
      {%Decimal{sign: 1, coef: coef} = price, ""} when is_integer(coef) and coef > 0 -> price
      _not_a_price -> nil
    end
  end

  defp above_zero(_not_text), do: nil

  defp get(path, options) do
    config = Application.fetch_env!(:regents, __MODULE__)

    Req.get(
      [
        base_url: Keyword.fetch!(config, :url),
        url: path,
        retry: false,
        redirect: false,
        connect_options: [timeout: 5_000],
        receive_timeout: 15_000
      ] ++ options
    )
  end
end
