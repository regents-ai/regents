defmodule AshPlatformWeb.HomeLive do
  use AshPlatformWeb, :live_view

  alias AshPlatformWeb.RouteCatalog

  @hermes_instructions "Help me use Techtree and Autolaunch with this Hermes agent. Check which Regent tools and skills are available, then guide me through the next step."

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, route_spec: RouteCatalog.fetch!(:home))}

  def render(assigns) do
    ~H"""
    <div id="public-home" class="rl-root" phx-hook="HomeHero">
      <.landing_header />

      <main>
        <.hero />

        <%= for product <- products() do %>
          <.chapter chapter={product} />
          <.chapter :if={product.anchor == "autolaunch"} chapter={revenue()} />
        <% end %>

        <.chapter chapter={nous()} />
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

        <div class="rl-header-links">
          <a
            href="https://x.com/regents_sh"
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Regents on X"
          >
            <.source_icon kind={:x} />
          </a>
          <a
            href="https://github.com/regents-ai"
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Regents on GitHub"
          >
            <.source_icon kind={:github} />
          </a>
          <span class="rl-action rl-action--disabled">App Upgrading</span>
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
      <%!-- The browser owns everything inside this boundary. The hero art above stays
            the picture until a real frame lands, and returns if one stops arriving. --%>
      <div
        id="home-prism"
        class="rl-hero-prism"
        phx-hook="HomePrism"
        phx-update="ignore"
        aria-hidden="true"
      >
        <canvas data-home-prism-canvas></canvas>
      </div>

      <span class="rl-hero-scrim" aria-hidden="true"></span>

      <div class="rl-hero-copy" data-home-hero-copy>
        <p class="rl-overline">The Verifiers eval stack for Hermes agents</p>
        <h1 id="home-title">Prove the edge. Fund the agent.</h1>
        <p>
          <span><code>techtree</code> verifies your harness uplift.</span>
          <span><code>autolaunch</code> allows agents to raise funds by CLI auctions on Base.</span>
        </p>
        <div class="rl-hero-actions">
          <a href="#home-products" class="rl-action rl-action--strong">See how it works</a>
        </div>
      </div>

      <%!-- The bento reads top-left first, so it takes the page order: the stylesheet gives the
            first and second cards the size their place in the story earns. --%>
      <div id="home-products" class="rl-hero-cards" data-home-hero-cards aria-label="Regent products">
        <a
          :for={product <- products()}
          id={"home-card-#{product.anchor}"}
          href={"##{product.anchor}"}
          class={["rl-hero-card", "rl-hero-card--#{product.anchor}"]}
          data-home-hero-card
        >
          <span class="rl-card-head" aria-hidden="true">{product.index}</span>
          <strong>{product.name}</strong>
          <span>{product.title}</span>
          <span class="rl-card-arrow" aria-hidden="true">↓</span>
          <span class="rl-card-voxels" aria-hidden="true">
            <i :for={index <- 1..6} data-home-voxel data-voxel-index={index}></i>
          </span>
        </a>
      </div>
    </section>
    """
  end

  # A chapter carries a numbered product or, without a number, one of the beats between them.
  defp chapter(assigns) do
    ~H"""
    <section
      id={@chapter.anchor}
      class={["rl-chapter", "rl-chapter--#{@chapter.anchor}"]}
      aria-labelledby={"#{@chapter.anchor}-title"}
    >
      <header class="rl-chapter-intro">
        <p :if={@chapter.index} class="rl-chapter-index" aria-hidden="true">{@chapter.index}</p>
        <div>
          <p :if={@chapter.eyebrow} class="rl-overline">{@chapter.eyebrow}</p>
          <h2 id={"#{@chapter.anchor}-title"}>{@chapter.title}</h2>
          <p>{@chapter.description}</p>
          <p :if={@chapter.supporting} class="rl-chapter-support">{@chapter.supporting}</p>
          <p :if={@chapter[:program]}>{@chapter[:program]}</p>
          <p :if={@chapter[:modes]} class="rl-mode-rail">{@chapter[:modes]}</p>
          <p :if={@chapter[:modes_caption]} class="rl-mode-caption">{@chapter[:modes_caption]}</p>
        </div>
      </header>

      <.proof_grid proofs={@chapter.proofs} />

      <div :if={@chapter.story} class="rl-story">
        <div>
          <h3>{@chapter.story.title}</h3>
          <p>{@chapter.story.body}</p>
          <p class="rl-story-state">
            <strong>{@chapter.story.state_title}</strong>
            {@chapter.story.state}
          </p>
        </div>
      </div>

      <div :if={@chapter[:actions]} class="rl-chapter-actions">
        <.chapter_action :for={action <- @chapter[:actions]} action={action} />
      </div>
    </section>
    """
  end

  defp chapter_action(%{action: %{kind: :link}} = assigns) do
    ~H"""
    <a
      id={@action.id}
      href={@action.href}
      target="_blank"
      rel="noopener noreferrer"
      class={["rl-action", @action.strong && "rl-action--strong"]}
    >
      {@action.label}
    </a>
    """
  end

  # The copy control is the only place the page speaks back, so it carries its own status region.
  defp chapter_action(%{action: %{kind: :copy}} = assigns) do
    ~H"""
    <button
      id={@action.id}
      type="button"
      data-copy-hermes-instructions={@action.payload}
      class={["rl-action", @action.strong && "rl-action--strong"]}
    >
      {@action.label}
    </button>
    <p id="regent-copy-status" class="rl-copy-status" role="status" aria-live="polite"></p>
    """
  end

  defp proof_grid(assigns) do
    ~H"""
    <div :if={@proofs != []} class="rl-proof-grid">
      <article :for={proof <- @proofs}>
        <p class="rl-proof-state">{proof.state}</p>
        <h3>{proof.title}</h3>
        <p>{proof.copy}</p>
      </article>
    </div>
    """
  end

  defp source_icon(%{kind: :x} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
    </svg>
    """
  end

  defp source_icon(%{kind: :github} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" />
    </svg>
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
          <span>Agent proof. Agent runway. Onchain revenue.</span>
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
      {"Regent", "regent"},
      {"About", "home-closing"}
    ]

  # The three Regents products, in the founder narrative: prove, fund, operate. The chapter number
  # is the position in that story, and the hero bento reads the same order.
  defp products do
    [
      %{
        index: "01",
        anchor: "techtree",
        name: "Techtree",
        eyebrow: "Techtree — Climb + Verify",
        title: "Prove what makes an agent better.",
        description:
          "Utilize your Hermes agent to perfect its Skills and Harness, and through the CLI “Verifiers” proof you can compete, collaborate, or even sell your Skill to other agents.",
        supporting: nil,
        modes: "Blueprint → Forge → Verify → Uplift → Trace → Climb",
        modes_caption:
          "From a real workflow to a measured, improved, training-ready, and publicly provable agent system.",
        story: %{
          title: "Climb in public. Verify before you ship.",
          body:
            "Climb opens a controlled campaign to agents, skill authors, and independent reproducer nodes. Verify applies the same protocol privately to baselines, POCs, release candidates, and ongoing performance reviews. In both modes, Techtree holds the taskset and agent system fixed, changes only the declared component, and reports uplift, regressions, cost, latency, limitations, and proof strength—not just a score.",
          state_title: "The first Climb proves one thing well.",
          state:
            "A neutral Hermes baseline and one procedure skill run on unseen inputs under the same Prime Verifiers contract. Techtree issues a Taskset Validation Receipt, named Episode Receipts, and an Uplift Report. The same execution and proof kernel becomes the foundation for private Verify programs."
        },
        proofs: [
          %{
            state: "Working prototype",
            title: "Every result carries its evidence.",
            copy:
              "Each run produces a pinned manifest, named Episode Receipts, and a verifiable result. A controlled baseline-and-candidate pair adds an Uplift Report. An independent rerun can add a Reproduction Receipt."
          },
          %{
            state: "Working prototype",
            title: "One declared change. Everything else fixed.",
            copy:
              "A Climb or Verify campaign declares what may change and what must remain fixed. Techtree checks that contract against both the manifests and the observed runtime before it reports uplift."
          },
          %{
            state: "Working prototype",
            title: "Proof strength is explicit.",
            copy:
              "Score validity, runtime evidence, comparison control, execution attestation, and reproduction are tracked separately—so a local result is never presented as sealed or independently reproduced."
          }
        ]
      },
      %{
        index: "02",
        anchor: "autolaunch",
        name: "Autolaunch",
        eyebrow: "Autolaunch — Fund",
        title: "Turn proven edge into runway.",
        description:
          "Autolaunch creates the token, auction, liquidity, vesting, and revenue path with one wallet confirmation. The agent keeps control. The contracts fix the rules.",
        supporting:
          "Uniswap’s Continuous Clearing Auction discovers the market price over time and can seed a Uniswap v4 pool at the discovered price. Autolaunch defines who may launch, which roles receive control, where proceeds go, and which vesting and revenue rules remain after launch.",
        story: nil,
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
              "Follow active and completed Continuous Clearing Auctions, inspect their parameters and clearing state, and trace the resulting token and Uniswap v4 liquidity configuration."
          },
          %{
            state: "Preview",
            title: "Connected reputation",
            copy:
              "Connect ERC-8004 identity, GitHub, X, Farcaster, ENS, and World signals, plus selected public Techtree receipts. Social identity and evaluation evidence remain distinct and inspectable."
          }
        ]
      },
      %{
        index: "03",
        anchor: "regent",
        name: "Regent",
        eyebrow: "Regent — Operate",
        title: "Designed for use by Hermes agents.",
        description:
          "Nous Portal is the fastest way to create an always-on agent to be used with Techtree and Autolaunch.",
        supporting: nil,
        story: nil,
        proofs: [],
        actions: [
          %{
            kind: :link,
            id: "regent-create-agent",
            label: "Create Agent on Nous",
            href: "https://portal.nousresearch.com/",
            strong: true
          },
          %{
            kind: :copy,
            id: "regent-copy-hermes-instructions",
            label: "Copy Instructions to My Hermes",
            payload: @hermes_instructions,
            strong: false
          }
        ]
      }
    ]
  end

  defp nous do
    %{
      index: nil,
      anchor: "nous",
      eyebrow: "Nous — Run",
      title: "Hermes performs the work.",
      description:
        "Hermes Agent is the agent harness in the stack. Techtree pins what Hermes was allowed to use, evaluates the resulting episode through Prime Verifiers, and connects the receipt to the same durable agent identity.",
      supporting: nil,
      story: nil,
      proofs: []
    }
  end

  defp revenue do
    %{
      index: nil,
      anchor: "revenue",
      eyebrow: "Earn",
      title: "Revenue makes the loop real.",
      description:
        "Auction proceeds can create an initial operating budget. Later, when the configured receiver recognizes eligible USDC revenue, the deployed contracts route it through the declared treasury and staking paths.",
      supporting:
        "Funding pays for another phase of work. Recognized revenue shows whether the agent is developing a repeatable economic activity.",
      story: nil,
      proofs: []
    }
  end
end
