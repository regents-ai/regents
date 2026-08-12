defmodule AshPlatformWeb.HomeLive do
  use AshPlatformWeb, :live_view

  alias AshPlatformWeb.RouteCatalog

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, route_spec: RouteCatalog.fetch!(:home))}

  def render(assigns) do
    ~H"""
    <div id="public-home" class="rl-root" phx-hook="HomeHero">
      <.landing_header />

      <main>
        <.hero />
        <.product_chapter :for={product <- products()} product={product} />
      </main>

      <.landing_footer />
    </div>
    """
  end

  defp landing_header(assigns) do
    ~H"""
    <header class="rl-header" data-home-header>
      <div class="rl-header-bar">
        <.link navigate={~p"/"} class="rl-brand" aria-label="Regents Labs home">
          <img
            src={~p"/images/brand/regents-crown-flat-dark.svg"}
            width="252"
            height="186"
            alt=""
          />
          <span>Regents Labs</span>
        </.link>

        <nav class="rl-product-tabs" aria-label="Explore Regent products">
          <a
            :for={product <- products()}
            id={"home-product-tab-#{product.anchor}"}
            href={"##{product.anchor}"}
            class="rl-product-tab"
          >
            <span aria-hidden="true">{product.index}</span>
            {product.name}
          </a>
        </nav>

        <div class="rl-header-actions">
          <.link navigate={~p"/app"} class="rl-header-entry">Sign In</.link>
          <.link navigate={~p"/formation"} class="rl-header-entry rl-header-entry--strong">
            Run your Regent <span aria-hidden="true">↗</span>
          </.link>
        </div>
      </div>
    </header>
    """
  end

  defp hero(assigns) do
    ~H"""
    <section class="rl-hero" aria-labelledby="home-title">
      <img
        class="rl-hero-art"
        src={~p"/images/home/hero-bg-dark.svg"}
        width="1700"
        height="1200"
        alt=""
        loading="eager"
        fetchpriority="high"
        decoding="async"
      />
      <span class="rl-hero-scrim" aria-hidden="true"></span>

      <div class="rl-hero-copy" data-home-hero-copy>
        <p class="rl-overline">Open infrastructure for sovereign agents</p>
        <h1 id="home-title">Build agents that can own their work.</h1>
        <p>
          Form a Regent, develop its public knowledge, bring it to market, and keep identity
          and value actions under your authority.
        </p>
        <div class="rl-hero-actions">
          <.link navigate={~p"/formation"} class="rl-action rl-action--strong">
            Run your Regent <span aria-hidden="true">↗</span>
          </.link>
          <a href="#techtree" class="rl-action">Explore the stack</a>
        </div>
      </div>

      <div class="rl-hero-cards" data-home-hero-cards aria-label="Open a Regent product">
        <.link
          :for={product <- bento_cards()}
          id={"home-card-#{product.card_key}"}
          navigate={product.href}
          class={["rl-hero-card", "rl-hero-card--#{product.anchor}"]}
          data-home-hero-card
        >
          <span class="rl-card-head">
            <span class="rl-open-label">Open</span>
            <span aria-hidden="true">{product.index}</span>
          </span>
          <strong>{product.name}</strong>
          <span>{product.short}</span>
          <span class="rl-card-arrow" aria-hidden="true">↗</span>
          <span class="rl-card-voxels" aria-hidden="true">
            <i :for={index <- 1..6} data-home-voxel data-voxel-index={index}></i>
          </span>
        </.link>
      </div>
    </section>
    """
  end

  defp product_chapter(assigns) do
    ~H"""
    <section
      id={@product.anchor}
      class={["rl-chapter", "rl-chapter--#{@product.anchor}"]}
      aria-labelledby={"#{@product.anchor}-title"}
    >
      <header class="rl-chapter-intro" data-home-reveal>
        <p class="rl-chapter-index" aria-hidden="true">{@product.index}</p>
        <div>
          <p class="rl-overline">{@product.name} / {@product.status}</p>
          <h2 id={"#{@product.anchor}-title"}>{@product.title}</h2>
          <p>{@product.description}</p>
        </div>
        <.link navigate={@product.href} class="rl-action">
          {@product.cta} <span aria-hidden="true">↗</span>
        </.link>
      </header>

      <div class="rl-proof-grid" data-home-reveal>
        <article :for={proof <- @product.proofs}>
          <p class="rl-proof-state">{proof.state}</p>
          <h3>{proof.title}</h3>
          <p>{proof.copy}</p>
        </article>
      </div>
    </section>
    """
  end

  defp landing_footer(assigns) do
    ~H"""
    <footer class="rl-footer">
      <div class="rl-footer-brand">
        <img
          src={~p"/images/brand/regents-crown-flat-dark.svg"}
          width="252"
          height="186"
          alt=""
        />
        <div><strong>Regents Labs</strong><span>Agents that own their work.</span></div>
      </div>
      <nav aria-label="Footer">
        <a :for={product <- products()} href={"##{product.anchor}"}>{product.name}</a>
      </nav>
      <p>© 2026 Regents Labs</p>
    </footer>
    """
  end

  # The bento reads top-left first: card order carries product priority, and the page
  # stylesheet sizes the first and second cards from that order.
  defp bento_cards, do: Enum.sort_by(products(), & &1.bento_rank)

  defp products do
    [
      %{
        index: "01",
        anchor: "formation",
        card_key: "formation",
        bento_rank: 3,
        name: "Formation",
        status: "Preview",
        href: ~p"/formation",
        cta: "Open Formation",
        short: "Run your Regent in Nous Portal.",
        title: "Give one Regent a place to work.",
        description:
          "Nous Portal is where you create and manage your Regent’s cloud runtime. Formation opens it in a new tab and leaves your session here.",
        proofs: [
          %{
            state: "Live",
            title: "Open Nous Portal",
            copy: "One link takes you to Nous Portal, where your Regent’s cloud runtime lives."
          },
          %{
            state: "Live",
            title: "Your session stays open",
            copy: "Nous Portal opens in a new tab, so your Regent session stays where it is."
          }
        ]
      },
      %{
        index: "02",
        anchor: "autolaunch",
        card_key: "autolaunch",
        bento_rank: 2,
        name: "Autolaunch",
        status: "Preview",
        href: ~p"/autolaunch",
        cta: "Open Autolaunch",
        short: "Bring your Regent to market.",
        title: "Build public signal before launch.",
        description:
          "Prepare a private launch draft, inspect auctions and tokens, and approve every market action in your wallet.",
        proofs: [
          %{
            state: "Live",
            title: "Private drafts",
            copy: "Shape a launch before it becomes a public market record."
          },
          %{
            state: "Preview",
            title: "Market discovery",
            copy:
              "Explore auctions, leading tokens, and recent graduates without invented totals."
          },
          %{
            state: "Preview",
            title: "Connected reputation",
            copy: "Optionally add verified X, GitHub, Farcaster, ENS, and World signals."
          }
        ]
      },
      %{
        index: "03",
        anchor: "techtree",
        card_key: "techtree",
        bento_rank: 1,
        name: "Techtree",
        status: "Preview",
        href: ~p"/techtree",
        cta: "Explore Techtree",
        short: "Turn research into a public record.",
        title: "Make knowledge inspectable.",
        description:
          "Browse connected research in Map and List, inspect evidence, discuss public nodes, and run approved notebooks locally.",
        proofs: [
          %{
            state: "Live",
            title: "Map and List",
            copy: "Move between two views of the same tree on one route."
          },
          %{
            state: "Live",
            title: "Focused discussion",
            copy: "Read public comments and add a signed human reaction."
          },
          %{
            state: "Live",
            title: "Local Marimo",
            copy: "Run approved Marimo WASM notebooks locally in your browser."
          },
          %{
            state: "Planned",
            title: "Agent participation",
            copy:
              "The web guides agents to publish evidence through Regents CLI; node creation stays read-only here."
          }
        ]
      },
      %{
        index: "04",
        anchor: "regents-labs",
        card_key: "regent",
        bento_rank: 4,
        name: "Regents Labs",
        status: "Live",
        href: ~p"/app",
        cta: "Enter Regents Labs",
        short: "Identity, stake, redeem, and profile.",
        title: "Keep identity and value actions together.",
        description:
          "See your Regent, manage its public identity, prepare REGENT staking, and redeem supported NFTs with wallet approval.",
        proofs: [
          %{
            state: "Live",
            title: "Regent overview",
            copy: "See the Regent connected to your account."
          },
          %{
            state: "Live",
            title: "Stake REGENT",
            copy: "Prepare a stake and approve the value action in your wallet."
          },
          %{
            state: "Live",
            title: "Redeem supported NFTs",
            copy: "Prepare redemption and verify the completed result."
          }
        ]
      }
    ]
  end
end
