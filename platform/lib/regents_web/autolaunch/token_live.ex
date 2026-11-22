defmodule RegentsWeb.Autolaunch.TokenLive do
  @moduledoc """
  A launched Base token's page, read only, which
  `RegentsWeb.Autolaunch.MarketPageLive` shows at the token's address: its
  heading, its price and market figures, a Revstake token's revenue, and who
  launched it with the launch's contracts.

  Once the page is open it reads, in the background and under one spend of
  the address's list reads (`RegentsWeb.Autolaunch.LiveListings.spend/2`),
  the token (`Regents.Autolaunch.TokenPage.read/2`), the dollar prices
  (`Regents.Autolaunch.UsdRates`), the token's revenue
  (`Regents.Autolaunch.TokenPage.revenue/2`) and, on a site given a Base
  deployment, the token's pool from the chain
  (`Regents.Autolaunch.TokenPage.pool/2`): its move, change and trades, its
  locker and pool id among the contracts, and its Uniswap button on Base.
  While the pool is being read, and when it could not be read, its figures
  show "…" and the rest of the page is shown as it is. The token's answer
  lands in `handle_async/3`, which shows the token and names the tab for it, as the
  page's first render does, so a token opened from a Tokens row or a Buy is
  named too; a page that shows no token is named "Token not found" or
  "Token unavailable". When the allowance is spent none of them is read and
  each is failed, so the page says the token could not be loaded, with Retry.
  Retry reads again only what failed, and only while nothing is being read.
  Until the dollar prices arrive, and when they could not be read, every
  figure is in the token's own currency.

  Still to come, each with its own part: the price chart and its chart link;
  the trade, stake and claim panel beside the figures; Share; the page
  rereading itself while open; the notices about reading the chain.
  """
  use RegentsWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias Regents.Autolaunch.{Lab, Token, TokenPage, UsdRates}
  alias RegentsWeb.Autolaunch.{LiveListings, PublicDocuments}

  alias RegentsWeb.Autolaunch.Components.{
    ChainIcon,
    CreatorLabel,
    LaunchTrust,
    Loading,
    MarketCard,
    RevenueHistory,
    TokenFigures,
    TokenHeading
  }

  # What the page reads in the background besides the token, once it is open.
  @reads [:rates, :revenue, :pool]

  def mount(%{"symbol" => symbol, "tail" => tail}, session, socket),
    do:
      {:ok,
       socket
       |> assign(
         client_tag: Map.fetch!(session, "client_tag"),
         symbol: symbol,
         tail: tail,
         status: :loading,
         record: nil,
         presentation: nil,
         connections: nil,
         unit: nil,
         pool: %AsyncResult{}
       )
       |> read(parts())}

  # Retry reads only what failed: a press with nothing failed, or while a read
  # is under way, starts none.
  def handle_event("retry", _params, socket) do
    if failed(socket) != [] and not loading?(socket),
      do: {:noreply, read(socket, failed(socket))},
      else: {:noreply, socket}
  end

  # An event no control on this page sends changes nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The token's answer: the page shows it and the tab is named for it.
  def handle_async(:page, {:ok, {:ok, %{token: token, creators: creators}}}, socket) do
    auction = token.auction

    {:noreply,
     socket
     |> assign(
       status: :ready,
       record: token,
       presentation: Token.presentation(token),
       connections: MarketCard.connections_for(token, creators),
       unit: MarketCard.entry_symbol(auction)
     )
     |> assign(PublicDocuments.market_page(:token, auction.title, auction.token_symbol))}
  end

  def handle_async(:page, {:ok, {:ok, nil}}, socket), do: {:noreply, shown(socket, :empty)}
  def handle_async(:page, _failure, socket), do: {:noreply, shown(socket, :error)}

  def render(assigns) do
    assigns =
      assign(assigns,
        rate: assigns.record && MarketCard.figure_rate(assigns.rates, assigns.record.auction),
        facts: if(assigns.pool.ok?, do: assigns.pool.result)
      )

    ~H"""
    <article :if={@status == :ready} id="autolaunch-token-detail" class="autolaunch-page token-page">
      <.link navigate={~p"/autolaunch/tokens"} class="market-back">← Tokens</.link>
      <header class="token-page__head">
        <TokenHeading.token_heading
          name={@presentation.name}
          symbol={@presentation.symbol}
          image={@presentation.image}
          currency={@unit}
          chain_id={@record.auction.chain_id}
          address={@record.auction.token_address}
          pool={@facts}
        >
          <:tags>
            <ChainIcon.chain_chip chain="Base" label="Base" />
            <Regent.Primitives.status>
              {LaunchTrust.launch_type(@record.auction)}
            </Regent.Primitives.status>
            <CreatorLabel.creator auction={@record.auction} connections={@connections} />
          </:tags>
        </TokenHeading.token_heading>
      </header>
      <div class="token-page__layout">
        <div class="token-page__overview">
          <TokenFigures.token_figures
            id="token-figures"
            price={@record.price_quote}
            unit={@unit}
            rate={@rate}
            pool={@pool}
          />
          <TokenFigures.market_stats
            id="token-market"
            auction={@record.auction}
            price={@record.price_quote}
            market_cap={@record.market_cap}
            unit={@unit}
            rate={@rate}
            pool={@pool}
          />
        </div>
        <div class="token-page__details">
          <RevenueHistory.revenue_history :if={@record.auction.kind == :agent} revenue={@revenue} />
          <LaunchTrust.token_facts
            auction={@record.auction}
            connections={@connections}
            pool={@facts}
          />
        </div>
      </div>
    </article>

    <div :if={@status == :loading} class="token-page__reading">
      <Loading.placeholder label="Reading the token" />
    </div>

    <section
      :if={@status == :empty}
      id="autolaunch-token-detail"
      class="autolaunch-page autolaunch-empty"
    >
      <Regent.Structure.section_bar>
        <h1 class="rg-section-bar__label">Token not found</h1>
      </Regent.Structure.section_bar>
      <p>This token is no longer listed.</p>
      <.link navigate={~p"/autolaunch/tokens"} class="rg-button rg-button--primary">
        <span class="rg-button__label">Return to Tokens</span>
      </.link>
    </section>

    <section
      :if={@status == :error}
      id="autolaunch-token-detail"
      class="autolaunch-page autolaunch-empty"
      role="alert"
    >
      <Regent.Structure.section_bar>
        <h1 class="rg-section-bar__label">Token unavailable</h1>
      </Regent.Structure.section_bar>
      <p>This token could not be loaded right now.</p>
      <Regent.Primitives.button phx-click="retry" variant="secondary">Retry</Regent.Primitives.button>
      <.link navigate={~p"/autolaunch/tokens"}>Return to Tokens</.link>
    </section>
    """
  end

  # Starts each of `parts` in the background under one spend of the address's
  # list reads, the token through `start_async` and the others through
  # `LiveListings`; when the allowance is spent, each is failed and none is
  # read.
  defp read(socket, parts) do
    %{symbol: symbol, tail: tail} = socket.assigns
    reads = for part <- parts, part != :page, do: {part, part(part, symbol, tail)}

    case {LiveListings.spend(socket, reads), :page in parts} do
      {{:ok, socket}, true} ->
        socket
        |> assign(:status, :loading)
        |> start_async(:page, fn -> TokenPage.read(symbol, tail) end)

      {{:limited, socket}, true} ->
        shown(socket, :error)

      {{_spent, socket}, false} ->
        socket
    end
  end

  # The token and its background reads; a site without a Base deployment has
  # no pool to read, and its pool's figures stay "…".
  defp parts do
    reads = if Lab.configured?(), do: @reads, else: List.delete(@reads, :pool)
    [:page | reads]
  end

  defp part(:rates, _symbol, _tail), do: fn -> {:ok, UsdRates.rates()} end
  defp part(:revenue, symbol, tail), do: fn -> TokenPage.revenue(symbol, tail) end
  defp part(:pool, symbol, tail), do: fn -> TokenPage.pool(symbol, tail) end

  # A page that shows no token, with the tab named for what it shows.
  defp shown(socket, :empty),
    do: socket |> assign(:status, :empty) |> assign(PublicDocuments.market_page(:token_not_found))

  defp shown(socket, :error),
    do:
      socket |> assign(:status, :error) |> assign(PublicDocuments.market_page(:token_unavailable))

  defp failed(socket) do
    page = if socket.assigns.status == :error, do: [:page], else: []
    page ++ Enum.filter(@reads, &socket.assigns[&1].failed)
  end

  defp loading?(socket),
    do: socket.assigns.status == :loading or Enum.any?(@reads, &socket.assigns[&1].loading)
end
