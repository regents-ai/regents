defmodule RegentsWeb.Autolaunch.Components.TokenFigures do
  @moduledoc """
  A token page's figures. `token_figures/1` opens the page: the price, large,
  with the price in the token's currency under it. `market_stats/1` follows:
  the market cap, the price in the currency, the change, the total supply, the
  number of trades and the launch type. Dollar figures are shown where the
  token's currency has a dollar price; otherwise every figure is in the
  currency. The figures settle in one after another as they arrive
  (`MotionCascade`).

  The change and the number of trades come from the token's pool, which this
  page does not read yet, so they show as autolaunch.sh showed them before its
  pool was read; so does the move since the pool opened, beside the price,
  which is left out until then.
  """
  use Phoenix.Component

  alias RegentsWeb.Autolaunch.Components.{LaunchTrust, MarketCard}
  alias RegentsWeb.Autolaunch.TokenDisplay

  attr :id, :string, required: true
  attr :price, :string, default: nil, doc: "the stored price per token, in the currency"
  attr :unit, :string, default: nil, doc: "the currency the token trades against"
  attr :rate, :any, default: nil, doc: "the currency's dollar price, nil while none is known"

  def token_figures(assigns) do
    assigns =
      assign(assigns, :length, MarketCard.price_length(assigns.price, assigns.unit, assigns.rate))

    ~H"""
    <div
      id={@id}
      class="token-figures"
      phx-hook="MotionCascade"
      data-variant={RegentsWeb.Motion.standard("grid")}
    >
      <p class="token-figures__price">
        <strong style={@length && "--figure-length: #{@length}"}>
          <MarketCard.price_figure amount={@price} unit={@unit} rate={@rate} />
          <span :if={!@price}>No price yet</span>
        </strong>
      </p>
      <p :if={@price && @rate} class="token-figures__unit">
        <TokenDisplay.price amount={@price} unit={@unit} />
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :auction, :map, required: true, doc: "the token's auction, for its supply and launch type"
  attr :price, :string, default: nil
  attr :market_cap, :any, default: nil, doc: "the price times the whole supply, in the currency"
  attr :unit, :string, default: nil
  attr :rate, :any, default: nil

  def market_stats(assigns) do
    assigns =
      assign(assigns,
        market_cap: MarketCard.money(assigns.market_cap, assigns.rate, assigns.unit),
        supply: assigns.auction.token_supply && RegentFormat.amount(assigns.auction.token_supply),
        launch_type: LaunchTrust.launch_type(assigns.auction)
      )

    ~H"""
    <section class="token-market" aria-labelledby={"#{@id}-title"}>
      <h2 id={"#{@id}-title"} class="token-page__title">Market</h2>
      <dl id={@id} class="token-market__stats">
        <div>
          <dt>Market cap</dt>
          <dd class="rg-figure">{@market_cap || "No price yet"}</dd>
        </div>
        <div>
          <dt>Price in {@unit}</dt>
          <dd class="rg-figure"><TokenDisplay.price amount={@price} /></dd>
        </div>
        <div>
          <dt>Change</dt>
          <dd class="rg-figure">…</dd>
        </div>
        <div>
          <dt>Total supply</dt>
          <dd class="rg-figure">{@supply || "Not read yet"}</dd>
        </div>
        <div>
          <dt>Trades</dt>
          <dd class="rg-figure">…</dd>
        </div>
        <div>
          <dt>Launch type</dt>
          <dd>{@launch_type}</dd>
        </div>
      </dl>
    </section>
    """
  end
end
