defmodule Regents.Keyfleet.Seasons.Rules do
  @moduledoc """
  How a season is scored and who takes the crown, as pure functions of the
  prices Coinbase sent, never floats.

  A pick's result over a season is `close / open - 1`; `USDC` is always 1, so
  it scores 0. A pick without both prices is void and scores nothing.

  When a season ends, the best pick is the one with the highest result, and of
  equal results the one locked first. It takes the crown for the next season
  when its product differs from the season's holding and its result beats the
  holding's own result over the season by more than the switching margin.
  Otherwise the holding and its captain stay. A holding without both prices
  has no result and doesn't defend: the best pick takes the crown with no
  margin, and with no pick scored the next season holds `USDC` with no
  captain.

  Every comparison multiplies whole numbers instead of dividing prices, so
  equal results are equal however many digits the prices have. A result
  kept on a pick or a season is `Decimal`'s division, to 28 digits, for
  showing; nothing is decided on it.
  """

  # How far the best pick's result must be above the holding's, over a season,
  # to take the crown.
  @switching_margin Decimal.new("0.01")

  @usdc "USDC"

  @type pick :: %{
          required(:product) => String.t(),
          required(:token_id) => pos_integer(),
          required(:lock_order) => pos_integer(),
          required(:open_price) => Decimal.t() | nil,
          required(:close_price) => Decimal.t() | nil,
          optional(atom()) => term()
        }

  @type season :: %{
          required(:holding) => String.t(),
          required(:captain_key) => pos_integer() | nil,
          required(:holding_open_price) => Decimal.t() | nil,
          required(:holding_close_price) => Decimal.t() | nil,
          optional(atom()) => term()
        }

  @doc "The switching margin."
  @spec switching_margin() :: Decimal.t()
  def switching_margin, do: @switching_margin

  @doc "`close / open - 1`, or nil without both prices."
  @spec result(Decimal.t() | nil, Decimal.t() | nil) :: Decimal.t() | nil
  def result(%Decimal{} = open, %Decimal{} = close),
    do: close |> Decimal.div(open) |> Decimal.sub(1)

  def result(_open, _close), do: nil

  @doc """
  What locking a pick at its season's start sets: its open price, or why it is
  void. `eligible` holds the products open to picks at the start, and `prices`
  each one's price then (nil for none).
  """
  @spec opening(pick(), MapSet.t(String.t()), %{String.t() => Decimal.t() | nil}) ::
          %{open_price: Decimal.t()} | %{void: :ineligible | :no_open_price}
  def opening(%{product: product}, eligible, prices) do
    cond do
      not MapSet.member?(eligible, product) -> %{void: :ineligible}
      price = Map.fetch!(prices, product) -> %{open_price: price}
      true -> %{void: :no_open_price}
    end
  end

  @doc """
  What settling a locked pick at its season's end sets: its close price and
  result, or that it is void. `prices` holds each product's price at the end.
  """
  @spec closing(pick(), %{String.t() => Decimal.t() | nil}) ::
          %{close_price: Decimal.t(), result: Decimal.t()} | %{void: :no_close_price}
  def closing(%{product: product, open_price: %Decimal{} = open}, prices) do
    case Map.fetch!(prices, product) do
      %Decimal{} = close -> %{close_price: close, result: result(open, close)}
      nil -> %{void: :no_close_price}
    end
  end

  @doc "The best pick with both prices: the highest result, and of equal ones the first locked."
  @spec best([pick()]) :: pick() | nil
  def best(picks) do
    picks
    |> Enum.filter(&scored?/1)
    |> Enum.sort_by(& &1.lock_order)
    |> Enum.reduce(nil, fn
      pick, nil -> pick
      pick, best -> if above?(pick, best), do: pick, else: best
    end)
  end

  @doc """
  The holding and captain for the season after `season`, from its scored
  picks, as `{holding, captain_key}`. With no season before, a fleet's first
  holds `USDC` with no captain.
  """
  @spec crown(season() | nil, [pick()]) :: {String.t(), pos_integer() | nil}
  def crown(nil, _picks), do: {@usdc, nil}

  def crown(%{holding: holding, captain_key: captain} = season, picks) do
    case {best(picks), holding_prices(season)} do
      {nil, nil} ->
        {@usdc, nil}

      {%{product: product, token_id: key}, nil} ->
        {product, key}

      {%{product: product, token_id: key} = best, prices} when product != holding ->
        if takes_crown?(best, prices), do: {product, key}, else: {holding, captain}

      {_none_or_the_holding, _prices} ->
        {holding, captain}
    end
  end

  @doc """
  What holding the fleet's holding through each of `seasons` came to: the
  product of each one's close over open, less one, where a holding without
  both prices counts as no change; nil when no season has both. The product
  is taken of whole numbers and divided once, so that division, to 28
  digits, is the only rounding.
  """
  @spec compounded([season()]) :: Decimal.t() | nil
  def compounded(seasons) do
    case seasons |> Enum.map(&holding_prices/1) |> Enum.reject(&is_nil/1) do
      [] ->
        nil

      priced ->
        {closes, opens} =
          Enum.reduce(priced, {1, 1}, fn {open, close}, {closes, opens} ->
            [close, open] = whole([close, open])
            {closes * close, opens * open}
          end)

        Decimal.div(closes - opens, opens)
    end
  end

  defp scored?(%{open_price: %Decimal{}, close_price: %Decimal{}}), do: true
  defp scored?(_void), do: false

  # a.close / a.open > b.close / b.open, every price being above 0.
  defp above?(a, b) do
    [a_close, a_open, b_close, b_open] =
      whole([a.close_price, a.open_price, b.close_price, b.open_price])

    a_close * b_open > b_close * a_open
  end

  # best.close / best.open - 1 > close / open - 1 + margin, with the margin as
  # `parts / per`, multiplied by best.open * open * per.
  defp takes_crown?(best, {holding_open, holding_close}) do
    [best_close, best_open, close, open] =
      whole([best.close_price, best.open_price, holding_close, holding_open])

    {parts, per} = fraction(@switching_margin)
    best_close * open * per > (close * per + parts * open) * best_open
  end

  # A holding's prices over its season, or nil without both: no result.
  defp holding_prices(%{
         holding_open_price: %Decimal{} = open,
         holding_close_price: %Decimal{} = close
       }),
       do: {open, close}

  defp holding_prices(_no_result), do: nil

  # Prices as whole numbers of the smallest unit any of them is written in,
  # so comparing them multiplies integers and rounds nothing.
  defp whole(prices) do
    unit = prices |> Enum.map(& &1.exp) |> Enum.min()
    Enum.map(prices, fn %Decimal{sign: 1, coef: coef, exp: exp} -> coef * 10 ** (exp - unit) end)
  end

  defp fraction(%Decimal{sign: 1, coef: coef, exp: exp}),
    do: {coef * 10 ** max(exp, 0), 10 ** max(-exp, 0)}
end
