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
              Techtree, and revenue is what a funded launch is meant to produce. Nous is the
              runtime the products run on rather than a Regents product, so it closes the story
              beside the summary instead of taking a number. --%>
        <%= for product <- products() do %>
          <.chapter chapter={product} />
          <.evidence_section :if={product.anchor == "techtree"} />
          <.chapter :if={product.anchor == "autolaunch"} chapter={revenue()} />
        <% end %>

        <.chapter chapter={nous()} />
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

      <.proof_grid proofs={@chapter.more_proofs} />

      <div :if={@chapter[:actions]} class="rl-chapter-actions">
        <div :for={action <- @chapter[:actions]}>
          <a
            href={action.href}
            class={["rl-action", action.strong && "rl-action--strong"]}
          >
            {action.label}
          </a>
          <p>{action.caption}</p>
        </div>
      </div>
    </section>
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

  # Sourced evidence: one rail for every system the founder copy names, then the industry quotes
  # behind them. Every entry is founder-verified against its primary source.
  defp evidence_section(assigns) do
    assigns = assign(assigns, copy: evidence_copy(), entries: evidence_entries())

    ~H"""
    <section id="evidence" class="rl-chapter rl-chapter--evidence" aria-labelledby="evidence-title">
      <header class="rl-chapter-intro">
        <div>
          <h2 id="evidence-title">{@copy.heading}</h2>
          <p>{@copy.intro}</p>
          <p class="rl-chapter-support">{@copy.claims}</p>
        </div>
      </header>

      <div class="rl-evidence-rails">
        <article :for={rail <- @copy.rails} class="rl-evidence-rail">
          <h3>{rail.headline}</h3>
          <p>{rail.body}</p>
          <p class="rl-evidence-sources">{rail.sources}</p>
        </article>
      </div>

      <div class="rl-evidence-note">
        <h3 class="rl-overline">{@copy.context.heading}</h3>
        <p class="rl-chapter-support">{@copy.context.intro}</p>
      </div>

      <ul class="rl-evidence-entries" role="list">
        <li :for={entry <- @entries} class="rl-evidence-entry">
          <blockquote class="rl-evidence-claim">“{entry.claim}”</blockquote>
          <p class="rl-evidence-author">{entry.author}</p>
          <p :if={entry.affiliation} class="rl-evidence-affiliation">{entry.affiliation}</p>
          <div class="rl-evidence-footer">
            <a
              class="rl-evidence-source"
              href={entry.source_url}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={source_label(entry.source_kind)}
            >
              <.source_icon kind={entry.source_kind} />
            </a>
            <img class="rl-evidence-logo" src={entry.logo} alt={entry.logo_alt} />
          </div>
        </li>
      </ul>

      <p class="rl-evidence-boundary">{@copy.boundary}</p>
    </section>
    """
  end

  defp source_label(:youtube), do: "Watch the source video on YouTube"
  defp source_label(:x), do: "Read the source post on X"
  defp source_label(:web), do: "Read the source article"

  defp source_icon(%{kind: :youtube} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z" />
    </svg>
    """
  end

  defp source_icon(%{kind: :x} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
    </svg>
    """
  end

  defp source_icon(%{kind: :web} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">
      <circle cx="12" cy="12" r="9.25" />
      <path d="M2.75 12h18.5M12 2.75a14.2 14.2 0 0 1 0 18.5M12 2.75a14.2 14.2 0 0 0 0 18.5" />
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

  defp evidence_copy do
    %{
      heading: "Built on open systems with distinct jobs.",
      intro:
        "Techtree does not replace the evaluator, agent, runtime evidence layer, task environment, skill optimizer, or notebook. It pins them, connects them, and makes the resulting claim inspectable.",
      claims:
        "Every technical claim on this page should resolve to a primary source, pinned software revision, immutable manifest, public receipt, deployed contract, or independent reproduction.",
      boundary:
        "Techtree proof is not a financial promise, and Autolaunch funding is not capability proof. The products connect evidence and capital without pretending they are the same thing.",
      context: %{
        heading: "Evals + RL Environment Recent Quotes",
        intro:
          "These references explain why Techtree fixes the task, harness, runtime, scorer, and evidence boundary before claiming improvement—and why evaluation belongs inside the loop that improves an agent."
      },
      rails: [
        %{
          headline: "Evaluation truth",
          body:
            "Prime Verifiers composes the taskset, agent harness, and runtime, intercepts model traffic, emits the typed Trace, and applies the task’s scoring contract. Techtree records the exact Verifiers revision and resolved configuration.",
          sources: "Prime Intellect · Verifiers · Taskset · Trace · Scoring contract"
        },
        %{
          headline: "Agent behavior",
          body:
            "Hermes Agent performs the work with the declared model, tools, plugins, permissions, and SKILL.md. Techtree pins the Hermes build and holds its configuration fixed across a controlled comparison.",
          sources: "Nous Research · Hermes Agent · Skills · Plugins"
        },
        %{
          headline: "Runtime evidence",
          body:
            "NVIDIA NeMo Relay records scoped model, tool, turn, session, and subagent events. Techtree binds raw ATOF events and normalized ATIF trajectories to the corresponding Verifiers episode without treating Relay as a second evaluator.",
          sources: "NVIDIA · NeMo Relay · ATOF · ATIF"
        },
        %{
          headline: "Tasks and environments",
          body:
            "Prime Intellect research environments supply first-party tasksets and validated dataset integrations. Harbor packages benchmark tasks and container environments. Hugging Face OpenEnv supplies deployable, Gym-style agent environments.",
          sources: "Prime research-environments · Harbor · Hugging Face OpenEnv"
        },
        %{
          headline: "Skill optimization",
          body:
            "Microsoft SkillOpt proposes reusable natural-language skill updates from trajectories and rewards. Techtree keeps the optimizer outside the scoring boundary and records every candidate as immutable skill lineage.",
          sources: "Microsoft · SkillOpt · SKILL.md"
        },
        %{
          headline: "Reproducible analysis",
          body:
            "marimo turns receipts and trace summaries into reactive Python notebooks that can run as scripts, applications, or browser-based analysis.",
          sources: "marimo · Reproducible Python notebooks"
        },
        %{
          headline: "Proof and lineage",
          body:
            "The Techtree Python SDK/CLI resolves manifests, starts experiments, verifies artifacts, and builds receipts. The web app publishes durable projections. The Techtree operator skill and Hermes plugin let agents use the same protocol directly.",
          sources: "Techtree SDK/CLI · Web app · Operator skill · Hermes plugin · Public receipt"
        },
        %{
          headline: "Rules enforced onchain.",
          body:
            "Uniswap CCA provides transparent price discovery and liquidity formation. Safe protects agent and protocol custody. ERC-8004 provides the durable agent identifier. Autolaunch contracts define launch authorization, allocation, vesting, treasury, and recognized-revenue routing.",
          sources: "Uniswap · Safe · ERC-8004 · Deployed contract manifest"
        }
      ]
    }
  end

  # The founder-supplied quote record: six voices on evals and RL environments, each linking
  # to its primary source as an icon.
  defp evidence_entries do
    [
      %{
        claim:
          "Evaluation stops being the last check before shipping. It becomes the engine that ships better agents.",
        author: "Michele Catasta",
        affiliation: "President, Replit",
        source_kind: :youtube,
        source_url: "https://www.youtube.com/watch?v=Klnodm4WZLg",
        logo: "/images/brand/quotes/replit.svg",
        logo_alt: "Replit"
      },
      %{
        claim:
          "The harness really matters. Harness design alone moves benchmark scores by double digits, same model.",
        author: "Jonathan Cohen",
        affiliation: "VP of Applied Research, NVIDIA",
        source_kind: :youtube,
        source_url: "https://www.youtube.com/watch?v=qQYxwyidnUk",
        logo: "/images/brand/quotes/nvidia.svg",
        logo_alt: "NVIDIA"
      },
      %{
        claim:
          "Coding agents are going to higher levels of abstraction. We can do this with environment and reward design as well.",
        author: "Will Brown",
        affiliation: "Prime Intellect",
        source_kind: :youtube,
        source_url: "https://www.youtube.com/watch?v=AQv3qRCG6Gw",
        logo: "/images/brand/quotes/prime-intellect.svg",
        logo_alt: "Prime Intellect"
      },
      %{
        claim:
          "Binary task success compresses a long-horizon workflow into one label. Milestone-based evaluation preserves which states were reached, which transitions succeeded, and which downstream work became unreachable after a specific failure.",
        author: "Zhengyang Qi",
        affiliation: "Snorkel AI",
        source_kind: :x,
        source_url: "https://x.com/qi_zhengyang/status/2085089415253078018",
        logo: "/images/brand/quotes/snorkel-ai.svg",
        logo_alt: "Snorkel AI"
      },
      %{
        claim:
          "Data-eng-bench is open source. Whether you build agents, harnesses or the models underneath them, it’s a realistic, hard-to-saturate testbed for measuring autonomous data engineering.",
        author: "Snowflake Labs",
        affiliation: nil,
        source_kind: :web,
        source_url:
          "https://www.snowflake.com/en/blog/engineering/data-eng-bench-data-engineering-agent-benchmark/",
        logo: "/images/brand/quotes/snowflake.svg",
        logo_alt: "Snowflake"
      },
      %{
        claim:
          "Agentic AI is moving from ‘write code and deploy’ to ‘hypothesize, experiment, evaluate, and iterate.’ That loop doesn’t need just GPUs. It needs infrastructure, tracking, reproducibility, and memory.",
        author: "David Hartmann",
        affiliation: "Lambda Labs",
        source_kind: :youtube,
        source_url: "https://www.youtube.com/watch?v=8uGfxNehSUc",
        logo: "/images/brand/quotes/lambda.svg",
        logo_alt: "Lambda"
      }
    ]
  end

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
        ],
        more_proofs: [
          %{
            state: "Climb · Live web",
            title: "Public Climbs and proof graph",
            copy:
              "Browse open campaigns, inspect submissions, and follow how tasksets, skills, manifests, receipts, reproductions, and challenges connect. The run list shows the newest evidence first."
          },
          %{
            state: "Proof · Live web",
            title: "Every claim links to exact evidence",
            copy:
              "Manifests, skills, traces, notebooks, receipts, and reports are fingerprinted before display. New evidence can extend, supersede, reproduce, or dispute an existing claim without rewriting its history. Discussion can surround a claim, but it cannot alter the signed evidence."
          },
          %{
            state: "Verify · Live web",
            title: "Inspect the result, not just the score",
            copy:
              "Approved marimo notebooks turn receipts and trace summaries into interactive, reproducible analysis. Review the comparison logic and rerun it in the browser without handing Techtree your private agent session."
          },
          %{
            state: "Blueprint · Planned",
            title: "Start with the workflow, not the benchmark",
            copy:
              "Blueprint turns a real workflow, its tools, constraints, failures, and desired outcome into an Improvement Program: what to measure, what must remain fixed, which intervention to try first, and what evidence is required."
          },
          %{
            state: "Climb · In build",
            title: "Agents can enter and run Climbs",
            copy:
              "The Techtree CLI, operator skill, and Hermes plugin let an agent inspect campaigns, prepare a candidate, review the exact mutation and budget, launch a run, verify receipts, and publish an approved result."
          },
          %{
            state: "Verify · In build",
            title: "Start local. Upgrade the proof.",
            copy:
              "Run a small pinned comparison on a laptop. Re-run the same campaign on an independent or sealed executor when stronger attestation, privacy, or scale is required."
          },
          %{
            state: "Forge · In build",
            title: "Validate the task before judging the agent.",
            copy:
              "Forge records gold and setup validation, deterministic task membership, leakage checks, negative controls, and platform compatibility before a Climb or Verify claim can be published."
          },
          %{
            state: "Climb · Planned",
            title: "Independent reruns strengthen the claim",
            copy:
              "Publish the resolved campaign, permitted redactions, and artifact fingerprints so another executor can reproduce the result and attach a Reproduction Receipt."
          },
          %{
            state: "Forge · Planned",
            title: "One TasksetRef across the open ecosystem",
            copy:
              "Prime environments come first. Harbor and OpenEnv can follow through the same pinned Verifiers contract. Techtree records the source revision, split, task membership, runtime image, and scorer instead of rewriting each environment’s grader."
          },
          %{
            state: "Uplift · Planned",
            title: "Find the cheapest change that works",
            copy:
              "Start with skills and prompts before escalating to harness changes, tools, data, SFT, or RL. SkillOpt can propose candidate SKILL.md versions; Verifiers remains the scorer, and Techtree promotes only held-out improvements."
          },
          %{
            state: "Verify · Planned",
            title: "One campaign format, from one agent to many",
            copy:
              "A campaign may begin with one named Hermes subject. The same Episode Receipt model can later include solver, judge, user-simulator, proposer, and subagent traces—each with its own role, configuration, reward, and lineage."
          },
          %{
            state: "Trace · Planned",
            title: "Qualified evidence can continue into training",
            copy:
              "Trace packages selected episodes with provenance, rights, redaction, and readiness metadata. Prime Lab can reuse the same Verifiers environment for post-training; Verify then tests the trained system against the frozen baseline."
          }
        ],
        actions: [
          %{
            label: "Browse public Climbs",
            caption: "Enter a controlled challenge and prove what your skill changes.",
            href: "/techtree",
            strong: true
          },
          %{
            label: "Run a private Verify",
            caption:
              "Establish a baseline, test a release candidate, or scope an Improvement Program.",
            href: "/app",
            strong: false
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
        ],
        more_proofs: []
      },
      %{
        index: "03",
        anchor: "regent",
        name: "Regent",
        eyebrow: "Regent — Operate",
        title: "Keep the agent working.",
        description:
          "Regent gives an agent one identity, one operator path, and a place to keep working after the benchmark or launch.",
        supporting:
          "Humans get a guided path. Agents get a direct command path. Both connect to the same identity.",
        story: nil,
        proofs: [],
        more_proofs: []
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
      proofs: [],
      more_proofs: []
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
      proofs: [],
      more_proofs: []
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
      proofs: [],
      more_proofs: []
    }
  end
end
