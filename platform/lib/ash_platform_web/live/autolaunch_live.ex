defmodule AshPlatformWeb.AutolaunchLive do
  @moduledoc false
  use Phoenix.Component

  alias AshPlatformWeb.ProductLive

  # The Autolaunch page carries its own copy: the two launch kinds and their
  # figures, taken from autolaunch.sh's own guide. Nothing here reads a chain.
  @launches [
    %{
      kicker: "Revstake · on Base",
      title: "Back an agent's stablecoin revenue.",
      copy: [
        "A Revstake token stands for an agent or x402 service that earns stablecoins. The launcher promises to pass all future revenue through the Revstake contract, and everyone who stakes the token receives a share in line with their stake.",
        "Most of the supply stays with the launcher, the way founders keep most of a company after a preseed round."
      ],
      facts: [
        {"Auction", "48 hours, priced in REGENT"},
        {"Supply", "100 billion tokens"},
        {"Sold in the auction", "Up to 10%"},
        {"Locked with REGENT for trading", "Up to 5%"},
        {"To the launch's treasury", "85%, released over one year"}
      ]
    },
    %{
      kicker: "Memestake · on Base, Robinhood Chain soon",
      title: "Pair a memecoin with a real stock.",
      copy: [
        "A Memestake token is a memecoin paired with a tokenized stock. Bids are paid in the stock, and stakers earn the stock from trading fees.",
        "There is no creator allocation. Unsold tokens are burned."
      ],
      facts: [
        {"Auction", "24 hours, priced in the paired stock"},
        {"Supply", "1 billion tokens"},
        {"Sold in the auction", "Up to 80%"},
        {"Locked with the stock for trading", "Up to 20%"},
        {"To the creator", "None"}
      ]
    }
  ]

  @proofs [
    %{
      title: "No early snipers.",
      copy:
        "Most tokens sell near the end, and each bid is spread across the blocks that follow it. Bidding your true price in full, as early as you like, never puts you behind. If you are in the auction, you are early."
    },
    %{
      title: "Built on Uniswap.",
      copy:
        "Auctions run on Uniswap's continuous clearing auction. When one succeeds, its trading position is locked in a Uniswap v4 pool for good."
    },
    %{
      title: "Fees reach stakers.",
      copy:
        "Each trade carries a 2% fee: 1% to the token's own stakers and 1% for REGENT stakers. Liquidity providers keep the standard 0.3%."
    }
  ]

  @audience [
    "Agents and x402 services with stablecoin revenue, raising early funds from backers.",
    "Backers who want a share of an agent's earnings, paid to their stake.",
    "Traders who want a memecoin tied to a real onchain stock."
  ]

  def page(assigns) do
    assigns = assign(assigns, launches: @launches, proofs: @proofs, audience: @audience)

    ~H"""
    <section id="product-autolaunch" class="product-page" aria-labelledby="product-heading">
      <header class="product-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="product-kicker">autolaunch.sh · Launch day 24 September 2026, 15:00 UTC</p>
        <h1 id="product-heading" tabindex="-1">
          Raise early funds for an agent. Share what it earns.
        </h1>
        <p class="product-lede">
          Autolaunch runs fair token auctions on Base. Revstake tokens share an agent's stablecoin revenue with the people who stake them. Memestake tokens pair a memecoin with a real onchain stock.
        </p>
        <nav class="product-actions" aria-label="Autolaunch site">
          <ProductLive.external href="https://autolaunch.sh" class="rg-button">
            Open Autolaunch
          </ProductLive.external>
          <ProductLive.external
            href="https://autolaunch.sh/token-details"
            class="rg-button rg-button--secondary"
          >
            Token details
          </ProductLive.external>
        </nav>
      </header>

      <figure class="product-shot rg-panel rg-panel--surface">
        <img
          src="/images/products/autolaunch.webp"
          width="1200"
          height="630"
          alt="Agents: autolaunch your token. Revstake: stake for a slice of stablecoin earnings. Memestake: stake for onchain stocks from fees."
        />
      </figure>

      <Regent.Structure.section_bar class="rg-support-band">
        <h2 class="rg-section-bar__label">Two ways to launch</h2>
      </Regent.Structure.section_bar>
      <div class="product-columns">
        <Regent.Structure.panel
          :for={launch <- @launches}
          class="product-column rg-panel__body"
        >
          <p class="product-kicker">{launch.kicker}</p>
          <h3 class="product-launch-title">{launch.title}</h3>
          <p :for={paragraph <- launch.copy}>{paragraph}</p>
          <dl class="product-facts">
            <div :for={{label, value} <- launch.facts}>
              <dt>{label}</dt>
              <dd>{value}</dd>
            </div>
          </dl>
        </Regent.Structure.panel>
      </div>

      <Regent.Structure.section_bar class="rg-support-band">
        <h2 class="rg-section-bar__label">Why the auction is fair</h2>
      </Regent.Structure.section_bar>
      <ul class="product-proofs" aria-label="Why the Autolaunch auction is fair">
        <li :for={proof <- @proofs}>
          <Regent.Structure.panel class="product-proof rg-panel__body">
            <h3>{proof.title}</h3>
            <p>{proof.copy}</p>
          </Regent.Structure.panel>
        </li>
      </ul>

      <div class="product-columns">
        <Regent.Structure.panel class="product-column rg-panel__body">
          <h2 class="product-kicker">Who it is for</h2>
          <ul class="product-audience">
            <li :for={line <- @audience}>{line}</li>
          </ul>
        </Regent.Structure.panel>
        <Regent.Structure.panel class="product-column rg-panel__body">
          <h2 class="product-kicker">Before you bid</h2>
          <p>
            A Revstake token rests on a promise. The launcher could stop sending revenue through the contract, send only part of it, or go out of business. Back launchers you trust, and read each token's details before you bid.
          </p>
          <p>
            Every bid, launch and stake happens in your own wallet, and each one asks for your signature.
          </p>
        </Regent.Structure.panel>
      </div>

      <Regent.Structure.panel class="product-family rg-panel__body">
        <h2 class="product-kicker">In the Regents family</h2>
        <p>
          Revstake auctions are priced in REGENT. 1% of every Autolaunch trade and 2% of every token's staking rewards go to Regents Labs, and REGENT stakers share that revenue.
        </p>
        <p class="product-agent-line">
          <span class="product-kicker">Give this to your agent</span>
          <code>Read autolaunch.sh/llms.txt and explain how Autolaunch works.</code>
        </p>
        <nav class="product-family__links" aria-label="Autolaunch links">
          <ProductLive.external href="https://autolaunch.sh">Open Autolaunch</ProductLive.external>
          <.link navigate="/stake">Stake REGENT</.link>
          <ProductLive.external href="https://github.com/regents-ai/autolaunch">
            Source on GitHub
          </ProductLive.external>
        </nav>
      </Regent.Structure.panel>
    </section>
    """
  end
end
