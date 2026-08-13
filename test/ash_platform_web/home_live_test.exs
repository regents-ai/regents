defmodule AshPlatformWeb.HomeLiveTest do
  use AshPlatformWeb.ConnCase, async: true

  # Nous is the runtime the products run on, not a Regents product: it has no tile and no number.
  @products [
    {"techtree", "Techtree", "Prove what makes an agent better."},
    {"autolaunch", "Autolaunch", "Turn proven edge into runway."},
    {"regent", "Regent", "Keep the agent working."}
  ]

  @nav [
    {"techtree", "Techtree", "#techtree"},
    {"autolaunch", "Autolaunch", "#autolaunch"},
    {"regent", "Regent", "#regent"},
    {"about", "About", "#home-closing"}
  ]

  # Prove, fund, earn, operate, run: the evidence follows the Techtree chapter it stands behind,
  # revenue follows the launch that produces it, and Nous and the summary close the product story.
  @sections ~w(techtree evidence autolaunch revenue regent nous product-summary home-closing)

  # Every section's founder copy: the eyebrows it shows, its headline, and its body paragraphs
  # in order, so a dropped or reordered supporting line fails here.
  @founder_copy [
    %{
      anchor: "techtree",
      eyebrows: ["Techtree — Climb + Verify"],
      title: "Prove what makes an agent better.",
      body: [
        "Utilize your Hermes agent to perfect its Skills and Harness, and through the CLI “Verifiers” proof you can compete, collaborate, or even sell your Skill to other agents.",
        "Blueprint → Forge → Verify → Uplift → Trace → Climb",
        "From a real workflow to a measured, improved, training-ready, and publicly provable agent system."
      ]
    },
    %{
      anchor: "autolaunch",
      eyebrows: ["Autolaunch — Fund"],
      title: "Turn proven edge into runway.",
      body: [
        "Autolaunch creates the token, auction, liquidity, vesting, and revenue path with one wallet confirmation. The agent keeps control. The contracts fix the rules.",
        "Uniswap’s Continuous Clearing Auction discovers the market price over time and can seed a Uniswap v4 pool at the discovered price. Autolaunch defines who may launch, which roles receive control, where proceeds go, and which vesting and revenue rules remain after launch."
      ]
    },
    %{
      anchor: "revenue",
      eyebrows: ["Earn"],
      title: "Revenue makes the loop real.",
      body: [
        "Auction proceeds can create an initial operating budget. Later, when the configured receiver recognizes eligible USDC revenue, the deployed contracts route it through the declared treasury and staking paths.",
        "Funding pays for another phase of work. Recognized revenue shows whether the agent is developing a repeatable economic activity."
      ]
    },
    %{
      anchor: "regent",
      eyebrows: ["Regent — Operate"],
      title: "Keep the agent working.",
      body: [
        "Regent gives an agent one identity, one operator path, and a place to keep working after the benchmark or launch.",
        "Humans get a guided path. Agents get a direct command path. Both connect to the same identity."
      ]
    },
    %{
      anchor: "nous",
      eyebrows: ["Nous — Run"],
      title: "Hermes performs the work.",
      body: [
        "Hermes Agent is the agent harness in the stack. Techtree pins what Hermes was allowed to use, evaluates the resulting episode through Prime Verifiers, and connects the receipt to the same durable agent identity."
      ]
    },
    %{
      anchor: "product-summary",
      eyebrows: [],
      title: "From benchmark to business.",
      body: [
        "Techtree proves the work. Autolaunch funds the next phase. Regent keeps the agent operating."
      ]
    }
  ]

  test "the header indexes the page and the bento reaches every chapter", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#public-home[phx-hook=HomeHero]")
    assert has_element?(view, "[data-home-header]")
    assert has_element?(view, "[data-home-hero-copy]")
    assert has_element?(view, "#home-products[data-home-hero-cards]")

    for {slug, label, target} <- @nav do
      assert has_element?(view, "#home-nav-#{slug}[href=\"#{target}\"]", label)
    end

    for {anchor, label, _tagline} <- @products do
      assert has_element?(
               view,
               "#home-card-#{anchor}[data-home-hero-card][href=\"##{anchor}\"]",
               label
             )

      assert has_element?(view, "##{anchor}.rl-chapter")
    end

    assert length(Regex.scan(~r/data-home-hero-card=""/, html)) == 3

    assert length(Regex.scan(~r/<section id="(?:techtree|autolaunch|regent)"/, html)) == 3
  end

  # The two campaign CTAs land on the launch holding page until the surfaces open, then become
  # the real destinations with no copy change.
  test "the public homepage never links into a route the launch gate holds", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    anchors = attribute(html, "[id]", "id")

    assert attribute(html, "#techtree .rl-chapter-actions a", "href") == ["/techtree", "/app"]

    assert texts(html, "#techtree .rl-chapter-actions div > p") == [
             "Enter a controlled challenge and prove what your skill changes.",
             "Establish a baseline, test a release candidate, or scope an Improvement Program."
           ]

    for href <- attribute(html, "a", "href") -- ["/techtree", "/app"],
        href != "/",
        not String.starts_with?(href, "https://") do
      assert String.starts_with?(href, "#")
      assert String.trim_leading(href, "#") in anchors
    end
  end

  test "every header control names a real destination", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, ~s(.rl-brand[href="/"]), "Regents Labs")
    assert has_element?(view, ".rl-header-note", "Proof, capital, and operations for agents.")

    assert attribute(html, ".rl-header a", "href") ==
             ["/" | Enum.map(@nav, &elem(&1, 2))]
  end

  test "the hero states the stack and offers one in-page way into it", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "h1#home-title", "Prove the edge. Fund the agent. Keep it running.")
    assert html =~ "The Verifiers eval stack for Hermes agents"

    assert has_element?(
             view,
             ".rl-hero-copy p",
             "techtree verifies your harness uplift. autolaunch allows agents to raise funds by CLI auctions on Base."
           )

    assert attribute(html, ".rl-hero-actions a", "href") == ["#home-products"]

    assert has_element?(
             view,
             ~s(.rl-hero-actions a.rl-action--strong[href="#home-products"]),
             "See how it works"
           )
  end

  test "the page closes on the system summary the About tab points at", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(section#home-closing[aria-labelledby="home-closing-title"] h2#home-closing-title),
             "Build the proof. Earn the trust. Launch when the work is ready."
           )

    assert has_element?(
             view,
             "#home-closing p",
             "Regents connects one agent identity across public work, capital formation, and continued operation."
           )

    assert attribute(html, "#home-closing a", "href") == ["#home-products"]

    assert has_element?(
             view,
             ~s(#home-closing a.rl-action--strong[href="#home-products"]),
             "Explore the system"
           )

    assert attribute(html, "main > section[id]", "id") == @sections
  end

  test "the footer carries the two company lines, a copyright, and no links", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ".rl-footer .rl-footer-brand strong",
             "Regents Labs builds Techtree and Autolaunch."
           )

    assert has_element?(
             view,
             ".rl-footer .rl-footer-brand span",
             "Agent proof. Agent runway. Onchain revenue."
           )

    assert has_element?(view, ".rl-footer p", "© 2026 Regents Labs")
    assert attribute(html, ".rl-footer a", "href") == []
  end

  test "the hero bento reads the page order and names each product in founder words", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    assert attribute(html, "[data-home-hero-card]", "id") ==
             Enum.map(@products, fn {anchor, _label, _tagline} -> "home-card-#{anchor}" end)

    assert texts(html, "[data-home-hero-card] strong") ==
             Enum.map(@products, &elem(&1, 1))

    assert texts(
             html,
             "[data-home-hero-card] > span:not(.rl-card-head, .rl-card-arrow, .rl-card-voxels)"
           ) == Enum.map(@products, &elem(&1, 2))
  end

  test "every section states its founder copy in order", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    for section <- @founder_copy do
      assert texts(html, "##{section.anchor} .rl-chapter-intro .rl-overline") == section.eyebrows

      assert has_element?(
               view,
               "section##{section.anchor}[aria-labelledby=\"#{section.anchor}-title\"] h2##{section.anchor}-title",
               section.title
             )

      assert texts(html, "##{section.anchor} .rl-chapter-intro div > p:not(.rl-overline)") ==
               section.body
    end
  end

  test "the section labels read prove, fund, earn, operate, and run", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert texts(html, "main .rl-chapter-intro .rl-overline") == [
             "Techtree — Climb + Verify",
             "Autolaunch — Fund",
             "Earn",
             "Regent — Operate",
             "Nous — Run"
           ]
  end

  test "the proof grids stand under the two products whose surfaces they describe", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert texts(html, "#techtree .rl-proof-grid article h3") == [
             "Every result carries its evidence.",
             "One declared change. Everything else fixed.",
             "Proof strength is explicit.",
             "Public Climbs and proof graph",
             "Every claim links to exact evidence",
             "Inspect the result, not just the score",
             "Start with the workflow, not the benchmark",
             "Agents can enter and run Climbs",
             "Start local. Upgrade the proof.",
             "Validate the task before judging the agent.",
             "Independent reruns strengthen the claim",
             "One TasksetRef across the open ecosystem",
             "Find the cheapest change that works",
             "One campaign format, from one agent to many",
             "Qualified evidence can continue into training"
           ]

    assert texts(html, "#techtree .rl-proof-grid article .rl-proof-state") == [
             "Working prototype",
             "Working prototype",
             "Working prototype",
             "Climb · Live web",
             "Proof · Live web",
             "Verify · Live web",
             "Blueprint · Planned",
             "Climb · In build",
             "Verify · In build",
             "Forge · In build",
             "Climb · Planned",
             "Forge · Planned",
             "Uplift · Planned",
             "Verify · Planned",
             "Trace · Planned"
           ]

    for proof <- ["Private drafts", "Market discovery", "Connected reputation"] do
      assert has_element?(view, "#autolaunch .rl-proof-grid article", proof)
    end

    assert texts(html, "#autolaunch .rl-proof-grid article .rl-proof-state") ==
             ["Live", "Preview", "Preview"]

    assert has_element?(
             view,
             "#techtree .rl-proof-grid article",
             "inspect campaigns, prepare a candidate, review the exact mutation and budget"
           )

    assert has_element?(
             view,
             "#autolaunch .rl-proof-grid article",
             "Connect ERC-8004 identity, GitHub, X, Farcaster, ENS, and World signals, plus selected public Techtree receipts."
           )
  end

  test "the hero preserves the approved art and readable server content", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(img.rl-hero-art[src="/images/home/hero-bg-dark.svg"][loading="eager"])
           )

    assert length(Regex.scan(~r/data-home-voxel=""/, html)) == 18

    refute html =~ "partners"
    refute html =~ "customers"
  end

  test "the page offers only the two actions the copy promises", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert texts(html, "a.rl-action") == [
             "See how it works",
             "Browse public Climbs",
             "Run a private Verify",
             "Explore the system"
           ]

    assert attribute(html, "#techtree .rl-chapter-actions a", "href") == ["/techtree", "/app"]
  end

  test "the homepage stays outside the application shell and within its HTML budget", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    refute html =~ ~s(id="app-shell")
    assert byte_size(html) <= 60 * 1024
  end

  test "the Techtree chapter carries the founder proof story", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "#techtree .rl-story h3",
             "Climb in public. Verify before you ship."
           )

    assert has_element?(
             view,
             "#techtree .rl-story p",
             "Climb opens a controlled campaign to agents, skill authors, and independent reproducer nodes. Verify applies the same protocol privately to baselines, POCs, release candidates, and ongoing performance reviews. In both modes, Techtree holds the taskset and agent system fixed, changes only the declared component, and reports uplift, regressions, cost, latency, limitations, and proof strength—not just a score."
           )

    assert has_element?(
             view,
             "#techtree .rl-story-state strong",
             "The first Climb proves one thing well."
           )

    assert has_element?(
             view,
             "#techtree .rl-story-state",
             "A neutral Hermes baseline and one procedure skill run on unseen inputs under the same Prime Verifiers contract. Techtree issues a Taskset Validation Receipt, named Episode Receipts, and an Uplift Report. The same execution and proof kernel becomes the foundation for private Verify programs."
           )
  end

  test "the evidence section states every stack rail and its source labels", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(section#evidence[aria-labelledby="evidence-title"] h2#evidence-title),
             "Built on open systems with distinct jobs."
           )

    assert texts(html, "#evidence .rl-chapter-intro div > p") == [
             "Techtree does not replace the evaluator, agent, runtime evidence layer, task environment, skill optimizer, or notebook. It pins them, connects them, and makes the resulting claim inspectable.",
             "Every technical claim on this page should resolve to a primary source, pinned software revision, immutable manifest, public receipt, deployed contract, or independent reproduction."
           ]

    assert texts(html, "#evidence .rl-evidence-rail h3") == [
             "Evaluation truth",
             "Agent behavior",
             "Runtime evidence",
             "Tasks and environments",
             "Skill optimization",
             "Reproducible analysis",
             "Proof and lineage",
             "Rules enforced onchain."
           ]

    assert has_element?(
             view,
             "#evidence .rl-evidence-rail p",
             "Prime Verifiers composes the taskset, agent harness, and runtime, intercepts model traffic, emits the typed Trace, and applies the task’s scoring contract. Techtree records the exact Verifiers revision and resolved configuration."
           )

    assert has_element?(
             view,
             "#evidence .rl-evidence-rail p",
             "Uniswap CCA provides transparent price discovery and liquidity formation. Safe protects agent and protocol custody. ERC-8004 provides the durable agent identifier. Autolaunch contracts define launch authorization, allocation, vesting, treasury, and recognized-revenue routing."
           )

    assert texts(html, "#evidence .rl-evidence-sources") == [
             "Prime Intellect · Verifiers · Taskset · Trace · Scoring contract",
             "Nous Research · Hermes Agent · Skills · Plugins",
             "NVIDIA · NeMo Relay · ATOF · ATIF",
             "Prime research-environments · Harbor · Hugging Face OpenEnv",
             "Microsoft · SkillOpt · SKILL.md",
             "marimo · Reproducible Python notebooks",
             "Techtree SDK/CLI · Web app · Operator skill · Hermes plugin · Public receipt",
             "Uniswap · Safe · ERC-8004 · Deployed contract manifest"
           ]

    assert has_element?(
             view,
             "#evidence .rl-evidence-note h3",
             "Evals + RL Environment Recent Quotes"
           )

    assert has_element?(
             view,
             "#evidence .rl-evidence-boundary",
             "Techtree proof is not a financial promise, and Autolaunch funding is not capability proof. The products connect evidence and capital without pretending they are the same thing."
           )

    assert has_element?(
             view,
             "#evidence .rl-evidence-note p",
             "These references explain why Techtree fixes the task, harness, runtime, scorer, and evidence boundary before claiming improvement—and why evaluation belongs inside the loop that improves an agent."
           )
  end

  test "the evidence record renders the six founder quotes with attribution", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, ~s(#evidence ul.rl-evidence-entries[role="list"]))

    assert texts(html, "#evidence blockquote.rl-evidence-claim") == [
             "“Evaluation stops being the last check before shipping. It becomes the engine that ships better agents.”",
             "“The harness really matters. Harness design alone moves benchmark scores by double digits, same model.”",
             "“Coding agents are going to higher levels of abstraction. We can do this with environment and reward design as well.”",
             "“Binary task success compresses a long-horizon workflow into one label. Milestone-based evaluation preserves which states were reached, which transitions succeeded, and which downstream work became unreachable after a specific failure.”",
             "“Data-eng-bench is open source. Whether you build agents, harnesses or the models underneath them, it’s a realistic, hard-to-saturate testbed for measuring autonomous data engineering.”",
             "“Agentic AI is moving from ‘write code and deploy’ to ‘hypothesize, experiment, evaluate, and iterate.’ That loop doesn’t need just GPUs. It needs infrastructure, tracking, reproducibility, and memory.”"
           ]

    assert texts(html, "#evidence .rl-evidence-author") == [
             "Michele Catasta",
             "Jonathan Cohen",
             "Will Brown",
             "Zhengyang Qi",
             "Snowflake Labs",
             "David Hartmann"
           ]

    assert texts(html, "#evidence .rl-evidence-affiliation") == [
             "President, Replit",
             "VP of Applied Research, NVIDIA",
             "Prime Intellect",
             "Snorkel AI",
             "Lambda Labs"
           ]

    assert attribute(html, "#evidence .rl-evidence-source", "aria-label") == [
             "Watch the source video on YouTube",
             "Watch the source video on YouTube",
             "Watch the source video on YouTube",
             "Read the source post on X",
             "Read the source article",
             "Watch the source video on YouTube"
           ]

    assert length(Regex.scan(~r/<svg/, html)) >= 6

    assert attribute(html, "#evidence .rl-evidence-logo", "alt") == [
             "Replit",
             "NVIDIA",
             "Prime Intellect",
             "Snorkel AI",
             "Snowflake",
             "Lambda"
           ]

    assert attribute(html, "#evidence .rl-evidence-logo", "src") == [
             "/images/brand/quotes/replit.svg",
             "/images/brand/quotes/nvidia.svg",
             "/images/brand/quotes/prime-intellect.svg",
             "/images/brand/quotes/snorkel-ai.svg",
             "/images/brand/quotes/snowflake.svg",
             "/images/brand/quotes/lambda.svg"
           ]
  end

  test "every primary source is an outbound link that leaves the page safely", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    sources = attribute(html, "#evidence .rl-evidence-source", "href")

    assert sources == [
             "https://www.youtube.com/watch?v=Klnodm4WZLg",
             "https://www.youtube.com/watch?v=qQYxwyidnUk",
             "https://www.youtube.com/watch?v=AQv3qRCG6Gw",
             "https://x.com/qi_zhengyang/status/2085089415253078018",
             "https://www.snowflake.com/en/blog/engineering/data-eng-bench-data-engineering-agent-benchmark/",
             "https://www.youtube.com/watch?v=8uGfxNehSUc"
           ]

    assert attribute(html, ~s(a[href^="https://"]), "href") == sources

    assert attribute(html, "#evidence .rl-evidence-source", "target") ==
             List.duplicate("_blank", 6)

    assert attribute(html, "#evidence .rl-evidence-source", "rel") ==
             List.duplicate("noopener noreferrer", 6)
  end

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp texts(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end
end
