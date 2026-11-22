defmodule RegentsWeb.Autolaunch.Components.PriceChart do
  @moduledoc """
  A graduated token's price since its pool opened, as one line in the colour
  of its image, under the token's price, with the low, the high and the
  number of trades beneath it. The figures come from
  `Regents.Autolaunch.PriceHistory`; the PriceChart hook draws the line with
  WebGPU. The caption says in words how far the price has moved, so a browser
  that cannot draw still reads it, and the same words give the page's Change
  and the move beside its price.

  The history carries two lines, one step per trade and 100 points evenly
  spread in time, and a "Trades / Time" choice picks which one the canvas
  draws. The trade line goes to the page as `[step, price]` pairs, so each
  trade takes the same width. The choice lives in the browser and survives the
  page's updates; a history whose `times` is nil has no choice.
  """
  use Phoenix.Component

  alias RegentsWeb.Autolaunch.TokenDisplay

  attr :id, :string, required: true
  attr :pool, Phoenix.LiveView.AsyncResult, required: true, doc: "the page's pool read"
  attr :unit, :string, required: true, doc: "the currency the price is in"
  attr :color, :string, default: nil, doc: "the image colour, or nil for the plain line"

  @doc """
  A token page's chart panel: its place while the pool is first read, then the
  line since the pool opened. A pool with a single price, like one that could
  not be read, shows no panel.
  """
  def pool_chart(
        %{pool: %{ok?: true, result: %{prices: %{points: [_first, _second | _rest]}}}} = assigns
      ) do
    ~H"""
    <Regent.Structure.panel class="token-page__chart">
      <.price_chart
        id={@id}
        label="Since the pool opened"
        history={@pool.result.prices}
        unit={@unit}
        color={@color}
      />
    </Regent.Structure.panel>
    """
  end

  def pool_chart(%{pool: %{ok?: false, loading: loading}} = assigns) when loading != nil do
    ~H"""
    <Regent.Structure.panel class="token-page__chart">
      <.price_chart_reading />
    </Regent.Structure.panel>
    """
  end

  def pool_chart(assigns), do: ~H""

  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "what the line is, e.g. since when"

  attr :history, :map,
    required: true,
    doc:
      "`points`, `times` (or nil), `low`, `high` and `trades`, as `Regents.Autolaunch.PriceHistory.pool/4` gives them"

  attr :unit, :string, required: true, doc: "the currency the price is in"
  attr :color, :string, default: nil, doc: "the image colour, or nil for the plain line"

  defp price_chart(assigns) do
    ~H"""
    <figure
      id={@id}
      class="price-chart"
      phx-hook="PriceChart"
      data-points={Jason.encode!(steps(@history.points))}
      data-times={@history.times && Jason.encode!(@history.times)}
      style={@color && "--image-color: #{@color}"}
    >
      <figcaption class="price-chart__caption">
        <span>{@label}</span>
        <span class="price-chart__change">{change(@history.points)}</span>
        <span
          :if={@history.times}
          id={"#{@id}-scale"}
          class="price-chart__scale"
          role="radiogroup"
          aria-label="Line"
          phx-update="ignore"
        >
          <label>
            <input type="radio" name={"#{@id}-scale"} value="points" checked />
            <span>Trades</span>
          </label>
          <label>
            <input type="radio" name={"#{@id}-scale"} value="times" />
            <span>Time</span>
          </label>
        </span>
      </figcaption>
      <canvas id={"#{@id}-line"} class="price-chart__line" phx-update="ignore" aria-hidden="true"></canvas>
      <dl class="price-chart__facts">
        <div>
          <dt>Low</dt>
          <dd><TokenDisplay.price amount={plain(@history.low)} unit={@unit} /></dd>
        </div>
        <div>
          <dt>High</dt>
          <dd><TokenDisplay.price amount={plain(@history.high)} unit={@unit} /></dd>
        </div>
        <div>
          <dt>Trades</dt>
          <dd>{@history.trades}</dd>
        </div>
      </dl>
    </figure>
    """
  end

  # The chart's place while the pool is first read, so the card keeps its height when the line arrives.
  defp price_chart_reading(assigns) do
    ~H"""
    <div class="price-chart" role="status">
      <span class="visually-hidden">Reading the price</span>
      <span class="loading-block price-chart__caption-reading" aria-hidden="true"></span>
      <span class="loading-block price-chart__line" aria-hidden="true"></span>
      <span class="loading-block price-chart__facts-reading" aria-hidden="true"></span>
    </div>
    """
  end

  @doc "How far a line of `[block, price]` points moved from its first price to its last, in words."
  @spec change([[number()]]) :: String.t()
  def change(points) do
    case move(points) do
      {:up, percent} -> "Up #{percent}%"
      {:down, percent} -> "Down #{percent}%"
      :unchanged -> "Unchanged"
    end
  end

  @doc """
  Which way a line of `[block, price]` points moved from its first price to its
  last, and by how many percent to one decimal place, or `:unchanged`.
  """
  @spec move([[number()]]) :: {:up | :down, float()} | :unchanged
  def move([[_block, first] | _rest] = points) do
    [_block, last] = List.last(points)
    percent = Float.round((last / first - 1) * 100, 1)

    cond do
      percent > 0 -> {:up, percent}
      percent < 0 -> {:down, abs(percent)}
      true -> :unchanged
    end
  end

  # The trade line's prices, one step apart.
  defp steps(points), do: points |> Enum.with_index(fn [_block, price], step -> [step, price] end)

  # A float price to six significant digits, which drops its binary noise.
  defp plain(price) do
    decimal = Decimal.from_float(price)
    %Decimal{coef: coef, exp: exp} = Decimal.normalize(decimal)

    decimal
    |> Decimal.round(6 - length(Integer.digits(coef)) - exp)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
