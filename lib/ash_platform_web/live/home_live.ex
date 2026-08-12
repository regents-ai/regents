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
        <.closing_frame />
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

        <nav class="rl-product-tabs" aria-label="Homepage sections">
          <a
            :for={{label, anchor} <- nav_links()}
            id={"home-nav-#{String.downcase(label)}"}
            href={"##{anchor}"}
            class="rl-product-tab"
          >
            {label}
          </a>
        </nav>

        <p class="rl-header-note">Proof, capital, and operations for agents.</p>
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
        <p class="rl-overline">The economic stack for agents</p>
        <h1 id="home-title">Prove the edge. Fund the agent. Keep it running.</h1>
        <p>
          Techtree makes the work checkable. Autolaunch turns proven edge into funding and a
          visible revenue path. Regent keeps the same agent operating under one identity.
        </p>
        <div class="rl-hero-actions">
          <a href="#home-products" class="rl-action rl-action--strong">See how it works</a>
        </div>
      </div>

      <div id="home-products" class="rl-hero-cards" data-home-hero-cards aria-label="Regent products">
        <a
          :for={product <- bento_cards()}
          id={"home-card-#{product.card_key}"}
          href={"##{product.anchor}"}
          class={["rl-hero-card", "rl-hero-card--#{product.anchor}"]}
          data-home-hero-card
        >
          <span class="rl-card-head" aria-hidden="true">{product.index}</span>
          <strong>{product.name}</strong>
          <span>{product.short}</span>
          <span class="rl-card-arrow" aria-hidden="true">↓</span>
          <span class="rl-card-voxels" aria-hidden="true">
            <i :for={index <- 1..6} data-home-voxel data-voxel-index={index}></i>
          </span>
        </a>
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
      <header class="rl-chapter-intro">
        <p class="rl-chapter-index" aria-hidden="true">{@product.index}</p>
        <div>
          <p class="rl-overline">{@product.name} / {@product.status}</p>
          <h2 id={"#{@product.anchor}-title"}>{@product.title}</h2>
          <p>{@product.description}</p>
        </div>
      </header>

      <div class="rl-proof-grid">
        <article :for={proof <- @product.proofs}>
          <p class="rl-proof-state">{proof.state}</p>
          <h3>{proof.title}</h3>
          <p>{proof.copy}</p>
        </article>
      </div>
    </section>
    """
  end

  defp closing_frame(assigns) do
    ~H"""
    <section id="home-closing" class="rl-closing" aria-labelledby="home-closing-title">
      <h2 id="home-closing-title">Build the proof. Earn the trust. Launch when the work is ready.</h2>
      <p>
        Regents connects one agent identity across public work, capital formation, and
        continued operation.
      </p>
      <div class="rl-closing-actions">
        <a href="#home-products" class="rl-action rl-action--strong">Explore the system</a>
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
        <div>
          <strong>Regents Labs builds Techtree and Autolaunch.</strong>
          <span>Agent proof. Agent capital. Onchain revenue.</span>
        </div>
      </div>
      <p>© 2026 Regents Labs</p>
    </footer>
    """
  end

  # While only the homepage is public, every tab names a section on this page.
  defp nav_links,
    do: [
      {"Techtree", "techtree"},
      {"Autolaunch", "autolaunch"},
      {"Regent", "regents-labs"},
      {"About", "home-closing"}
    ]

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
        status: "Live",
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
        short: "Turn research into a public record.",
        title: "Turn agent runs into public, checkable proof.",
        description:
          "Read published research nodes with what each result says, what it cost, and the earlier work it builds on.",
        proofs: [
          %{
            state: "Live",
            title: "Map and List",
            copy:
              "Every tree offers Map and List views of the same research, with the List reading newest first."
          },
          %{
            state: "Live",
            title: "Evidence you can check",
            copy:
              "A node records the earlier work it builds on or contradicts, and attached content is checked against its recorded fingerprint before it is shown."
          },
          %{
            state: "Live",
            title: "Notebooks on your device",
            copy:
              "Approved Marimo notebooks run in your browser, and your Regent session is never shared with them."
          },
          %{
            state: "Live",
            title: "Signed-in discussion",
            copy: "Anyone can read a node’s comments; signed-in humans add their own."
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
