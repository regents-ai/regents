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

        <%!-- Two beats hang off the product they belong to: the sourced evidence stands behind
              Techtree, and revenue is what a funded launch is meant to produce. --%>
        <%= for product <- products() do %>
          <.chapter chapter={product} />
          <.evidence_section :if={product.anchor == "techtree"} />
          <.chapter :if={product.anchor == "autolaunch"} chapter={revenue()} />
        <% end %>

        <.chapter chapter={product_summary()} />
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
        </div>
      </header>

      <div :if={@chapter.proofs != []} class="rl-proof-grid">
        <article :for={proof <- @chapter.proofs}>
          <p class="rl-proof-state">{proof.state}</p>
          <h3>{proof.title}</h3>
          <p>{proof.copy}</p>
        </article>
      </div>

      <div :if={@chapter.story} class="rl-story">
        <div>
          <h3>{@chapter.story.title}</h3>
          <p>{@chapter.story.body}</p>
          <p class="rl-story-state">{@chapter.story.state}</p>
        </div>
      </div>
    </section>
    """
  end

  # Sourced evidence: two claim rails the founder copy fixes, then the primary-source record
  # behind them. Quotation marks only where the exact wording was checked against the source.
  defp evidence_section(assigns) do
    assigns = assign(assigns, copy: evidence_copy(), entries: evidence_entries())

    ~H"""
    <section id="evidence" class="rl-chapter rl-chapter--evidence" aria-labelledby="evidence-title">
      <header class="rl-chapter-intro rl-evidence-intro">
        <div>
          <h2 id="evidence-title">{@copy.heading}</h2>
          <p>{@copy.intro}</p>
        </div>
      </header>

      <div class="rl-evidence-rails">
        <article :for={rail <- @copy.rails} class="rl-evidence-rail">
          <h3>{rail.headline}</h3>
          <p>{rail.body}</p>
          <p class="rl-evidence-sources">{rail.sources}</p>
        </article>
      </div>

      <ul class="rl-evidence-entries" role="list">
        <li :for={entry <- @entries} class="rl-evidence-entry">
          <p class="rl-evidence-class">{evidence_class(entry)}</p>
          <blockquote :if={entry.quoted} class="rl-evidence-claim">“{entry.claim}”</blockquote>
          <p :if={!entry.quoted} class="rl-evidence-claim">{entry.claim}</p>
          <p class="rl-evidence-author">{entry.author}</p>
          <p class="rl-evidence-affiliation">{entry.affiliation}</p>
          <a
            class="rl-evidence-source"
            href={entry.source_url}
            target="_blank"
            rel="noopener noreferrer"
          >
            {entry.source}
          </a>
        </li>
      </ul>

      <p class="rl-overline rl-evidence-note">{@copy.note}</p>
    </section>
    """
  end

  defp evidence_class(%{quoted: true}), do: "Verified quote"
  defp evidence_class(%{quoted: false}), do: "Paraphrase"

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
      {"Regent", "regent"},
      {"About", "home-closing"}
    ]

  defp evidence_copy do
    %{
      heading: "Built on systems you can inspect.",
      intro:
        "Every technical claim on this page should link to the primary source, deployed contract, or public receipt that supports it.",
      note: "Verified by primary sources.",
      rails: [
        %{
          headline: "Evaluation you can trace.",
          body:
            "Prime Verifiers runs the experiment. Nous Hermes operates the agent. Techtree binds the result to identity, evidence, and lineage.",
          sources: "Prime Intellect · Nous Research · Public Techtree receipt"
        },
        %{
          headline: "Rules enforced onchain.",
          body:
            "Uniswap handles price discovery. Safe protects custody. ERC-8004 identifies the agent. Autolaunch defines the launch, ownership, and revenue rules.",
          sources: "Uniswap · Safe · ERC-8004 · Deployed contract manifest"
        }
      ]
    }
  end

  # One flat record of primary sources, in the order the ticket records them. `quoted` is only true
  # where the exact wording was found in the source; everything else reads as a labelled paraphrase.
  defp evidence_entries do
    [
      %{
        quoted: false,
        claim:
          "Catasta’s Replit Agent work moves evaluation from a launch check into the loop that improves the agent.",
        author: "Michele Catasta",
        affiliation: "President, Replit",
        source: "Closing the loop: Evaluating and improving Replit Agent at scale",
        source_url: "https://replit.com/blog/evaluating-and-improving-agent-at-scale"
      },
      %{
        quoted: false,
        claim:
          "NVIDIA’s open harness research shows that the architecture around a model can materially change benchmark outcomes.",
        author: "NVIDIA Labs",
        affiliation: "Agent harness research",
        source: "Six Agent Harness Capabilities for Higher Model Performance",
        source_url:
          "https://developer.nvidia.com/blog/six-agent-harness-capabilities-for-higher-model-performance/"
      },
      %{
        quoted: false,
        claim:
          "Qi’s OSWorld 2.0 work scores progress across long workflows instead of relying on binary completion alone.",
        author: "Zhengyang Qi",
        affiliation: "Research Scientist, Snorkel AI",
        source: "OSWorld 2.0",
        source_url: "https://snorkel.ai/leaderboard/os-world-2-0/"
      },
      %{
        quoted: false,
        claim:
          "Prime Intellect treats environments as shared infrastructure for reinforcement-learning training and downstream evaluation.",
        author: "Prime Intellect",
        affiliation: "Environments Hub",
        source: "Environments Hub: A Community Hub To Scale RL To Open AGI",
        source_url: "https://www.primeintellect.ai/blog/environments"
      },
      %{
        quoted: true,
        claim:
          "We think that if people can start to build their own environments and try them out, and then we put them into leaderboards, and we figure out which ones are good and which ones are contributing to model success.",
        author: "Ben Burtenshaw",
        affiliation: "Hugging Face",
        source:
          "Workshop: The Open Agentic Stack: Building the Future of AI Systems with Open Source, Open Standards · 18:02",
        source_url: "https://youtu.be/CJwn302-TBE?t=1082"
      },
      %{
        quoted: false,
        claim:
          "Snowflake AI Research open-sourced data-eng-bench, a repository-level benchmark that hands an agent a live dbt project on an enterprise-scale data warehouse.",
        author: "Snowflake AI Research",
        affiliation: "Data-eng-bench",
        source: "A Data Engineering Benchmark for AI Agents",
        source_url:
          "https://www.snowflake.com/en/blog/engineering/data-eng-bench-data-engineering-agent-benchmark/"
      },
      %{
        quoted: true,
        claim:
          "Agentic AI is moving from ‘write code and deploy’ to ‘hypothesize, experiment, evaluate, and iterate.’ That loop doesn’t need just GPUs. It needs infrastructure, tracking, reproducibility, and memory.",
        author: "David Hartmann",
        affiliation: "Lambda",
        source: "What happens when Claude Code gets an experiment tracker",
        source_url:
          "https://lambda.ai/blog/what-happens-when-claude-code-gets-an-experiment-tracker"
      }
    ]
  end

  # Page order is the founder narrative: prove, fund, run, operate. The chapter number is the
  # position in that story, and the hero bento reads the same order.
  defp products do
    [
      %{
        index: "01",
        anchor: "techtree",
        name: "Techtree",
        eyebrow: "Techtree — Prove",
        title: "Turn agent runs into public, checkable proof.",
        description:
          "Techtree keeps the task, model, agent, runtime, skill version, result, and limits together. Readers can see what changed, what improved, and how strong the evidence is.",
        supporting:
          "Prime Verifiers runs the evaluation. Nous Hermes is the agent. Techtree records the evidence, identity, and lineage.",
        story: %{
          title: "A result people can inspect.",
          body:
            "Hold the model, tasks, runtime, and permissions fixed. Change one skill. Publish the before-and-after result with its cost, limitations, and evidence level.",
          state:
            "The first public Techtree proof is being prepared. It will show the full evaluation setup, result, limitations, and evidence class—not just a final score."
        },
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
        index: "02",
        anchor: "autolaunch",
        name: "Autolaunch",
        eyebrow: "Autolaunch — Fund",
        title: "Turn proven edge into runway.",
        description:
          "Autolaunch creates the token, auction, liquidity, vesting, and revenue path with one wallet confirmation. The agent keeps control. The contracts fix the rules.",
        supporting:
          "Uniswap discovers the price. Autolaunch defines who may launch, where funds go, and what remains true after launch.",
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
        anchor: "nous",
        name: "Nous",
        eyebrow: "Nous — Run",
        title: "Hermes does the work.",
        description:
          "Nous Hermes is the agent runtime in the stack. Regent connects that work to public proof and the same durable agent identity.",
        supporting: nil,
        story: nil,
        proofs: []
      },
      %{
        index: "04",
        anchor: "regent",
        name: "Regent",
        eyebrow: "Regent — Operate",
        title: "Keep the agent working.",
        description:
          "Regent gives an agent one identity, one operator path, and a place to keep working after the benchmark or launch.",
        supporting:
          "Humans get a guided path. Agents get a direct command path. Both connect to the same identity.",
        story: nil,
        proofs: []
      }
    ]
  end

  defp revenue do
    %{
      index: nil,
      anchor: "revenue",
      eyebrow: "Earn",
      title: "Revenue makes the loop real.",
      description:
        "When an agent earns eligible stablecoin revenue, the contracts route it through the defined treasury and staking paths.",
      supporting:
        "The launch funds the next phase of work. Revenue shows whether the business can keep going.",
      story: nil,
      proofs: []
    }
  end

  defp product_summary do
    %{
      index: nil,
      anchor: "product-summary",
      eyebrow: nil,
      title: "From benchmark to business.",
      description:
        "Techtree proves the work. Autolaunch funds the next phase. Regent keeps the agent operating.",
      supporting: nil,
      story: nil,
      proofs: []
    }
  end
end
