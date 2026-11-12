defmodule RegentsWeb.AutolaunchLive do
  @moduledoc false
  use Phoenix.Component

  alias RegentsWeb.{HomeLive, ProductLive}

  # The Autolaunch page carries its own copy: the two launch kinds and their
  # figures, taken from autolaunch.sh's own guide, onchain stocks first.
  # Nothing here reads a chain. The product directory serves the same copy
  # through `content/0`.
  @launches [
    %{
      kicker: "Memestock · on Base, Robinhood Chain soon",
      title: "Pair a memecoin with a real stock.",
      copy: [
        "A Memestock token is a memecoin paired with a tokenized stock. Bids are paid in the stock, and stakers earn the stock from trading fees.",
        "There is no creator allocation. Unsold tokens are burned."
      ],
      facts: [
        %{label: "Auction", value: "24 hours, priced in the paired stock"},
        %{label: "Supply", value: "1 billion tokens"},
        %{label: "Sold in the auction", value: "Up to 80%"},
        %{label: "Locked with the stock for trading", value: "Up to 20%"},
        %{label: "To the creator", value: "None"}
      ]
    },
    %{
      kicker: "Revstake · on Base",
      title: "Back an agent's stablecoin revenue.",
      copy: [
        "A Revstake token stands for an agent or x402 service that earns stablecoins. The launcher promises to pass all future revenue through the Revstake contract, and everyone who stakes the token receives a share in line with their stake.",
        "Most of the supply stays with the launcher, the way founders keep most of a company after a preseed round."
      ],
      facts: [
        %{label: "Auction", value: "48 hours, priced in REGENT"},
        %{label: "Supply", value: "100 billion tokens"},
        %{label: "Sold in the auction", value: "Up to 10%"},
        %{label: "Locked with REGENT for trading", value: "Up to 5%"},
        %{label: "To the launch's treasury", value: "85%, released over one year"}
      ]
    }
  ]

  # autolaunch.sh's "Principles" row (`AutolaunchWeb.HomeLive`, autolaunch 11a5c8ba).
  @cards [
    %{
      id: "autolaunch/clearing",
      name: "Fair price",
      headline: "One price for every bidder.",
      line: "Bids above the clearing price all pay that price, not their own limit.",
      tint: "#ff5b19",
      action: "Read rules",
      href: "https://autolaunch.sh/how-it-works#how-it-works-auction"
    },
    %{
      id: "autolaunch/vault",
      name: "Locked liquidity",
      headline: "Liquidity no one can pull.",
      line: "It sits in a contract that can only collect trading fees.",
      tint: "#4fd3ec",
      action: "See fees",
      href: "https://autolaunch.sh/how-it-works#how-it-works-fees"
    },
    %{
      id: "autolaunch/address",
      name: "Stock tokens",
      headline: "Every stock named exactly.",
      line: "Each stock shows its issuer and chain, and its exact address before you sign.",
      tint: "#00c805",
      action: "See stocks",
      href: "https://autolaunch.sh/stocks"
    },
    %{
      id: "autolaunch/signature",
      name: "Your wallet",
      headline: "Your wallet signs everything.",
      line: "Autolaunch never holds your keys or your money.",
      tint: "#e5e3d2",
      action: "See portfolio",
      href: "https://autolaunch.sh/portfolio"
    },
    %{
      id: "autolaunch/handoff",
      name: "Agents",
      headline: "Agents prepare, you sign.",
      line: "A paired agent can fill in your launch for you to check and sign.",
      tint: "#f5c16c",
      action: "Pair agent",
      href: "https://autolaunch.sh/account/agents"
    },
    %{
      id: "autolaunch/blocks",
      name: "Onchain",
      headline: "Figures from the chain.",
      line: "Auction prices, bids and amounts raised come from the auction contracts.",
      tint: "#aecacd",
      action: "See auctions",
      href: "https://autolaunch.sh/auctions"
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
        "Each trade pays 1% to the token's own stakers and 1% to REGENT stakers. The pool also charges the standard 0.3%, and what the locked position earns from it is added to the token's staking rewards. These rates are fixed in the contracts."
    }
  ]

  @audience [
    "Agents and x402 services with stablecoin revenue, raising early funds from backers.",
    "Backers who want a share of an agent's earnings, paid to their stake.",
    "Traders who want a memecoin tied to a real onchain stock."
  ]

  @doc """
  What the Autolaunch page shows, as the product directory also serves it. The
  home page's chapter supplies the heading and summary, and its directory entry
  the site and source links, so that copy still lives once.
  """
  def content do
    chapter = Enum.find(HomeLive.products(), &(&1.anchor == "autolaunch"))
    site = Enum.find(HomeLive.hero_products(), &(&1.name == "autolaunch"))

    %{
      name: "Autolaunch",
      domain: "autolaunch.sh",
      site: site.site,
      github: site.github,
      kicker: "autolaunch.sh · Auctions opened 24 September 2026",
      headline: chapter.title,
      summary: chapter.description,
      cards: @cards,
      launches: @launches,
      why_fair: @proofs,
      audience: @audience,
      before_you_bid: [
        "A Revstake token rests on a promise. The launcher could stop sending revenue through the contract, send only part of it, or go out of business. Back launchers you trust, and read each token's details before you bid.",
        "Every bid, launch and stake happens in your own wallet, and each one asks for your signature."
      ],
      family:
        "Revstake auctions are priced in REGENT. 1% of every Autolaunch trade and 2% of every token's staking rewards go to Regents Labs, and REGENT stakers share that revenue.",
      agent_line: "Read autolaunch.sh/llms.txt and explain how Autolaunch works.",
      start: %{label: "How it works", href: "https://autolaunch.sh/how-it-works"}
    }
  end

  def page(assigns) do
    assigns = assign(assigns, content: content())

    ~H"""
    <section id="product-autolaunch" class="product-page" aria-labelledby="product-heading">
      <header class="product-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="product-kicker">{@content.kicker}</p>
        <h1 id="product-heading" tabindex="-1">{@content.headline}</h1>
        <p class="product-lede">{@content.summary}</p>
        <nav class="product-actions" aria-label="Autolaunch site">
          <a href={@content.site} target="_blank" rel="noopener noreferrer" class="rg-button">
            <span class="rg-button__label">Open {@content.name}<span class="visually-hidden">, opens in a new tab</span></span>
          </a>
          <a
            href={@content.start.href}
            target="_blank"
            rel="noopener noreferrer"
            class="rg-button rg-button--secondary"
          >
            <span class="rg-button__label">{@content.start.label}<span class="visually-hidden">, opens in a new tab</span></span>
          </a>
        </nav>
      </header>

      <ProductLive.cards cards={@content.cards} />

      <figure class="product-shot rg-panel rg-panel--surface">
        <img
          src="/images/products/autolaunch.webp"
          width="1200"
          height="630"
          alt="Agents: autolaunch your token. Revstake: stake for a slice of stablecoin earnings. Memestock: stake for onchain stocks from fees."
        />
      </figure>

      <Regent.Structure.section_bar class="rg-support-band">
        <h2 class="rg-section-bar__label">Launches</h2>
      </Regent.Structure.section_bar>
      <div class="product-columns">
        <Regent.Structure.panel
          :for={launch <- @content.launches}
          class="product-column rg-panel__body"
        >
          <p class="product-kicker">{launch.kicker}</p>
          <h3 class="product-launch-title">{launch.title}</h3>
          <p :for={paragraph <- launch.copy}>{paragraph}</p>
          <dl class="product-facts">
            <div :for={fact <- launch.facts}>
              <dt>{fact.label}</dt>
              <dd>{fact.value}</dd>
            </div>
          </dl>
        </Regent.Structure.panel>
      </div>

      <Regent.Structure.section_bar class="rg-support-band">
        <h2 class="rg-section-bar__label">Fair auction</h2>
      </Regent.Structure.section_bar>
      <ul class="product-proofs" aria-label="Fair auction">
        <li :for={proof <- @content.why_fair}>
          <Regent.Structure.panel class="product-proof rg-panel__body">
            <h3>{proof.title}</h3>
            <p>{proof.copy}</p>
          </Regent.Structure.panel>
        </li>
      </ul>

      <div class="product-columns">
        <Regent.Structure.panel class="product-column rg-panel__body">
          <h2 class="product-kicker">Audience</h2>
          <ul class="product-audience">
            <li :for={line <- @content.audience}>{line}</li>
          </ul>
        </Regent.Structure.panel>
        <Regent.Structure.panel class="product-column rg-panel__body">
          <h2 class="product-kicker">Risks</h2>
          <p :for={paragraph <- @content.before_you_bid}>{paragraph}</p>
        </Regent.Structure.panel>
      </div>

      <Regent.Structure.panel class="product-family rg-panel__body">
        <h2 class="product-kicker">Regents family</h2>
        <p>{@content.family}</p>
        <p class="product-agent-line">
          <span class="product-kicker">Agent prompt</span>
          <code>{@content.agent_line}</code>
        </p>
        <nav class="product-family__links" aria-label="Autolaunch links">
          <ProductLive.external href={@content.site}>Open {@content.name}</ProductLive.external>
          <.link navigate="/stake">Stake REGENT</.link>
          <ProductLive.external href={@content.github}>Source on GitHub</ProductLive.external>
        </nav>
      </Regent.Structure.panel>
    </section>
    """
  end
end
