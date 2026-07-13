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
            Form a Regent <span aria-hidden="true">↗</span>
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
            Form a Regent <span aria-hidden="true">↗</span>
          </.link>
          <a href="#techtree" class="rl-action">Explore the stack</a>
        </div>
      </div>

      <div class="rl-hero-cards" data-home-hero-cards aria-label="Open a Regent product">
        <.link
          :for={product <- products()}
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

  defp products do
    [
      %{
        index: "01",
        anchor: "formation",
        card_key: "formation",
        name: "Formation",
        status: "Preview",
        href: ~p"/formation",
        cta: "Open Formation",
        short: "Form and operate your cloud Regent.",
        title: "Give one Regent a place to work.",
        description:
          "Bring identity, a private cloud runtime, Hermes Skills, and practical prepaid operations into one guided lifecycle.",
        proofs: [
          %{
            state: "Preview",
            title: "One active Regent",
            copy: "See how one Regent stays connected to your signed-in account."
          },
          %{
            state: "Preview",
            title: "Private cloud",
            copy: "Explore the private cloud workspace and controls planned for your Regent."
          },
          %{
            state: "Preview",
            title: "Hermes Skills",
            copy: "Keep runtime skills in the same Formation lifecycle."
          }
        ]
      },
      %{
        index: "02",
        anchor: "autolaunch",
        card_key: "autolaunch",
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
            state: "Preview",
            title: "Private drafts",
            copy: "See how a launch takes shape before it becomes a public market record."
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
            copy: "Optionally add verified X, Farcaster, ENS, and World signals."
          }
        ]
      },
      %{
        index: "03",
        anchor: "techtree",
        card_key: "techtree",
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
            state: "Preview",
            title: "Map and List",
            copy: "See how two views reveal the same research tree."
          },
          %{
            state: "Preview",
            title: "Focused discussion",
            copy: "Preview public comments and signed human reactions on each node."
          },
          %{
            state: "Preview",
            title: "Local Marimo",
            copy: "Preview approved Marimo WASM notebooks that run locally in your browser."
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
        name: "Regents Labs",
        status: "Preview",
        href: ~p"/app",
        cta: "Enter Regents Labs",
        short: "Identity and future wallet actions.",
        title: "Keep identity and value actions together.",
        description:
          "Preview the home for your Regent identity, public profile, and future wallet-approved value actions.",
        proofs: [
          %{
            state: "Preview",
            title: "Regent overview",
            copy: "See where the Regent connected to your account will appear."
          },
          %{
            state: "Preview",
            title: "Stake REGENT",
            copy: "Review where wallet-approved staking will live; actions are not available yet."
          },
          %{
            state: "Preview",
            title: "Redeem supported NFTs",
            copy: "Review where supported redemption will live; actions are not available yet."
          }
        ]
      }
    ]
  end
end
