defmodule RegentsWeb.AutolaunchLive do
  @moduledoc false

  alias RegentsWeb.HomeLive

  # Autolaunch's copy for the product directory (`content/0`): the two launch
  # kinds and their figures for new launches, taken from autolaunch.sh's How it
  # works and its README (autolaunch a45f7c95), onchain stocks first.
  # Nothing here reads a chain.
  @launches [
    %{
      kicker: "Memestock · on Base and Robinhood Chain",
      title: "Pair a memecoin with a real stock.",
      copy: [
        "A Memestock token is a memecoin paired with a tokenized stock. Bids are paid in the stock, and stakers earn the stock from trading fees.",
        "The creator receives 0.5% of the supply and earns a share of trading fees. If the auction misses its minimum, every bidder takes back their full bid and every token is retired."
      ],
      facts: [
        %{label: "Auction", value: "About 24 hours, priced in the stock"},
        %{label: "Supply", value: "1 billion tokens"},
        %{label: "Sold", value: "49.75%"},
        %{label: "Liquidity", value: "49.75%, locked with the stock for good"},
        %{label: "Creator", value: "0.5%, released over 30 days from graduation"}
      ]
    },
    %{
      kicker: "Revstake · on Base",
      title: "Back an agent's stablecoin revenue.",
      copy: [
        "A Revstake token stands for an agent or x402 service that earns stablecoins. The launcher promises to pass its revenue through the token's staking contract, and stakers share that revenue and the token's trading fees by how much of the whole supply they stake.",
        "Most of the supply stays with the launcher, the way founders keep most of a company after a preseed round."
      ],
      facts: [
        %{label: "Auction", value: "About 2 days, priced in REGENT"},
        %{label: "Supply", value: "100 billion tokens"},
        %{label: "Sold", value: "20%"},
        %{label: "Liquidity", value: "Up to 10%, locked with REGENT for good"},
        %{label: "Treasury", value: "70%, released over one year"}
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
      href: "https://regents.sh/docs/autolaunch"
    },
    %{
      id: "autolaunch/vault",
      name: "Locked liquidity",
      headline: "Liquidity no one can pull.",
      line: "It sits in a contract that can only collect trading fees.",
      tint: "#4fd3ec",
      action: "See fees",
      href: "https://regents.sh/docs/autolaunch"
    },
    %{
      id: "autolaunch/address",
      name: "Stock tokens",
      headline: "Every stock named exactly.",
      line: "Each stock shows its issuer and chain, and its exact address before you sign.",
      tint: "#00c805",
      action: "See stocks",
      href: "https://regents.sh/autolaunch/app"
    },
    %{
      id: "autolaunch/signature",
      name: "Your wallet",
      headline: "Your wallet signs everything.",
      line: "Autolaunch never holds your keys or your money.",
      tint: "#e5e3d2",
      action: "See portfolio",
      href: "https://regents.sh/autolaunch/portfolio"
    },
    %{
      id: "autolaunch/handoff",
      name: "Agents",
      headline: "Agents prepare, you sign.",
      line: "A paired agent can fill in your launch for you to check and sign.",
      tint: "#f5c16c",
      action: "Pair agent",
      href: "https://regents.sh/account/agents"
    },
    %{
      id: "autolaunch/blocks",
      name: "Onchain",
      headline: "Figures from the chain.",
      line: "Auction prices, bids and amounts raised come from the auction contracts.",
      tint: "#aecacd",
      action: "See auctions",
      href: "https://regents.sh/autolaunch/auctions"
    }
  ]

  @proofs [
    %{
      title: "No early snipers.",
      copy:
        "Tokens sell a little at a time over the whole auction, not all at once at the end. Bids above the clearing price buy at that price, not at their own limit, and your average price depends on when your bid was buying. If you are in the auction, you are early."
    },
    %{
      title: "Built on Uniswap.",
      copy:
        "Auctions run on Uniswap's continuous clearing auction. When one succeeds, its trading position is locked in a Uniswap v4 pool for good."
    },
    %{
      title: "Fees reach stakers.",
      copy:
        "Revstake trades pay 3%: 2% to the token's staking pot and 1% to REGENT staking, or to the Regent Safe when it is collected in the token itself. Memestock trades pay 4.3% on the stock amount of every trade: 3% to the token's stakers, 1% to Regent and 0.3% to the creator. On Base that 1% becomes USDC for REGENT staking; on Robinhood Chain it is held as USDG until a bridge to Base is built. Both pools also charge the standard 0.3%, and what the locked liquidity earns goes to the token's staking. The rates are fixed in the contracts."
    }
  ]

  @audience [
    "Agents and x402 services with stablecoin revenue, raising early funds from backers.",
    "Backers who want a share of an agent's earnings, paid to their stake.",
    "Traders who want a memecoin tied to a real onchain stock.",
    "Holders of a Base stock token who sell covered calls on it and keep the premium, and buyers who pay for calls in USDC."
  ]

  @doc """
  Autolaunch's entry as the product directory serves it. The home page's
  chapter supplies the heading and summary, and its directory entry the site
  and source links, so that copy still lives once.
  """
  def content do
    chapter = Enum.find(HomeLive.products(), &(&1.anchor == "autolaunch"))
    site = Enum.find(HomeLive.hero_products(), &(&1.name == "autolaunch"))

    %{
      name: "Autolaunch",
      domain: "regents.sh/autolaunch",
      site: site.site,
      github: site.github,
      kicker: "regents.sh/autolaunch · Auctions opened 24 September 2026",
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
        "Revstake auctions are priced in REGENT, and what Autolaunch earns is converted to USDC and split with $REGENT stakers.",
      agent_line: "Read regents.sh/docs/autolaunch and explain how Autolaunch works.",
      start: %{label: "Open Autolaunch", href: "https://regents.sh/autolaunch/app"}
    }
  end
end
