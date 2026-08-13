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
        </div>
      </header>

      <.proof_grid proofs={@chapter.proofs} />

      <div :if={@chapter.story} class="rl-story">
        <div>
          <h3>{@chapter.story.title}</h3>
          <p>{@chapter.story.body}</p>
          <p class="rl-story-state">{@chapter.story.state}</p>
        </div>
      </div>

      <.proof_grid proofs={@chapter.more_proofs} />
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

  # Sourced evidence: one rail for every system the founder copy names, then the research context
  # behind them. Quotation marks only where the exact wording was checked against the source.
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
      heading: "Built on open systems with distinct jobs.",
      intro:
        "Techtree does not replace the evaluator, agent, runtime evidence layer, task environment, skill optimizer, or notebook. It pins them, connects them, and makes the resulting claim inspectable.",
      claims:
        "Every technical claim on this page should resolve to a primary source, pinned software revision, immutable manifest, public receipt, deployed contract, or independent reproduction.",
      context: %{
        heading: "Research context, verified by primary sources.",
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
            "Nous Hermes performs the work with the declared model, tools, plugins, permissions, and SKILL.md. Techtree pins the Hermes build and holds its configuration fixed across a controlled comparison.",
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

  # The three Regents products, in the founder narrative: prove, fund, operate. The chapter number
  # is the position in that story, and the hero bento reads the same order.
  defp products do
    [
      %{
        index: "01",
        anchor: "techtree",
        name: "Techtree",
        eyebrow: "Techtree — Prove",
        title: "Turn agent evaluations into public, checkable proof.",
        description:
          "Techtree pins the taskset, agent harness, model, skill, tools, runtime, scorer, and exact task membership into one experiment manifest. It binds the resulting traces, rewards, costs, and limitations into a receipt people can verify.",
        supporting:
          "Prime Verifiers owns evaluation and reward truth. Nous Hermes performs the work. NVIDIA NeMo Relay captures runtime scopes and trajectory evidence. Techtree binds the manifest, traces, identity, and lineage into a checkable claim.",
        story: %{
          title: "A controlled comparison people can inspect.",
          body:
            "Hold the task membership, model, Hermes version, tools, runtime, sampling settings, and scorer fixed. Change only the declared skill. Techtree verifies that boundary, pairs results task by task, and publishes uplift, regressions, cost, latency, limitations, and evidence grade.",
          state:
            "The first proof starts small on purpose. The first public Techtree proof will pair a neutral baseline with a procedure skill on unseen inputs. A hidden deterministic scorer, a Prime Verifiers trace, and NVIDIA NeMo Relay trajectory evidence will expose the complete path from experiment manifest to Skill Uplift Report—not just a final score."
        },
        proofs: [
          %{
            state: "Working prototype",
            title: "A proof is a set of artifacts.",
            copy:
              "One evaluated run produces an immutable manifest and a Run Receipt. A controlled baseline-and-candidate pair produces a Skill Uplift Report. An independent rerun can add a Reproduction Receipt."
          },
          %{
            state: "Working prototype",
            title: "Proof of a declared experiment.",
            copy:
              "A Techtree proof shows what was tested, what was held fixed, what changed, and what the declared scorer observed. It does not turn one benchmark result into a universal capability claim."
          },
          %{
            state: "Working prototype",
            title: "Not every result proves the same thing.",
            copy:
              "Techtree labels whether a result is merely recorded, integrity-bound, controlled, independently reproduced, or sealed. A score may be valid while some runtime evidence is incomplete; the receipt says so instead of hiding the distinction."
          }
        ],
        more_proofs: [
          %{
            state: "Live web",
            title: "Proof graph and run list",
            copy:
              "The Map shows how tasksets, skills, manifests, receipts, reproductions, and challenges connect. The List shows the same evidence newest first."
          },
          %{
            state: "Live web",
            title: "Content-addressed evidence",
            copy:
              "Every manifest, skill, trace bundle, notebook, receipt, and report is referenced by a content fingerprint. Techtree verifies the fingerprint before displaying the artifact and records the exact work each claim builds on, reproduces, or contradicts."
          },
          %{
            state: "Live web",
            title: "Reproducible analysis with marimo",
            copy:
              "Approved marimo notebooks turn receipts and trace summaries into interactive analysis. They can run as reproducible Python programs in the browser without receiving the user’s Regent session."
          },
          %{
            state: "Live web",
            title: "Claims and comments stay separate",
            copy:
              "Anyone can inspect the evidence. Signed-in humans can discuss it, but comments never alter the manifest, score, receipt, or proof grade."
          },
          %{
            state: "In build",
            title: "Agent-native operation",
            copy:
              "Agents can use the Techtree Python SDK/CLI, an operator SKILL.md, or the Techtree Hermes plugin to resolve manifests, start runs, inspect receipts, compare skills, and publish approved claims. The web app presents the same durable objects."
          },
          %{
            state: "In build",
            title: "Start on a laptop. Reproduce in a sandbox.",
            copy:
              "Run a small experiment locally in pinned Docker. Move the same taskset, Hermes harness, and manifest to remote runtimes when stronger isolation or greater scale is required."
          },
          %{
            state: "In build",
            title: "Validate the task before judging the agent.",
            copy:
              "Techtree records whether the taskset passed gold-path, no-op, membership, determinism, and leakage checks before an uplift claim can be published."
          },
          %{
            state: "Planned",
            title: "Proof gets stronger when someone else can rerun it.",
            copy:
              "Publish the resolved manifest, receipt, artifact fingerprints, and permitted redactions so another executor can reproduce the experiment and attach an independent Reproduction Receipt."
          },
          %{
            state: "Planned",
            title: "Tasksets from the open ecosystem",
            copy:
              "Prime Intellect research environments are the first source. Harbor benchmarks and Hugging Face OpenEnv deployments follow behind the same pinned experiment boundary. Techtree records the source revision, split, task membership, runtime image, and scoring contract instead of rewriting each environment’s grader."
          },
          %{
            state: "Planned",
            title: "Improve the skill without changing the model.",
            copy:
              "Microsoft SkillOpt proposes trajectory-driven edits to a reusable SKILL.md. Techtree snapshots every candidate, evaluates it through the same Prime Verifiers contract, and promotes it only after validation. The optimizer can propose the change. It cannot grade its own work."
          },
          %{
            state: "Planned",
            title: "One proof format, from one agent to many.",
            copy:
              "A Techtree episode may begin with one Hermes trace. The same receipt model can later contain solver, judge, user-simulator, proposer, and subagent traces—each with its own role, configuration, reward, and lineage."
          },
          %{
            state: "Planned",
            title: "The same environment can continue into training.",
            copy:
              "When an evaluation is ready for optimization, Prime RL can consume the same Verifiers configurations and traces. Techtree records which evidence justified the training run—and requires the resulting model or skill to be evaluated again before a new capability claim is published."
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
        "Nous Hermes is the agent harness in the stack. Techtree pins what Hermes was allowed to use, evaluates the resulting episode through Prime Verifiers, and connects the receipt to the same durable agent identity.",
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
        "When an agent earns eligible stablecoin revenue, the contracts route it through the defined treasury and staking paths.",
      supporting:
        "The launch funds the next phase of work. Revenue shows whether the business can keep going.",
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
