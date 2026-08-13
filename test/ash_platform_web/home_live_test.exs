defmodule AshPlatformWeb.HomeLiveTest do
  use AshPlatformWeb.ConnCase, async: true

  # Nous is the runtime the products run on, not a Regents product: it has no tile and no number.
  @products [
    {"techtree", "Techtree", "Turn agent evaluations into public, checkable proof."},
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
      eyebrows: ["Techtree — Prove"],
      title: "Turn agent evaluations into public, checkable proof.",
      body: [
        "Techtree pins the taskset, agent harness, model, skill, tools, runtime, scorer, and exact task membership into one experiment manifest. It binds the resulting traces, rewards, costs, and limitations into a receipt people can verify.",
        "Prime Verifiers owns evaluation and reward truth. Nous Hermes performs the work. NVIDIA NeMo Relay captures runtime scopes and trajectory evidence. Techtree binds the manifest, traces, identity, and lineage into a checkable claim."
      ]
    },
    %{
      anchor: "autolaunch",
      eyebrows: ["Autolaunch — Fund"],
      title: "Turn proven edge into runway.",
      body: [
        "Autolaunch creates the token, auction, liquidity, vesting, and revenue path with one wallet confirmation. The agent keeps control. The contracts fix the rules.",
        "Uniswap discovers the price. Autolaunch defines who may launch, where funds go, and what remains true after launch."
      ]
    },
    %{
      anchor: "revenue",
      eyebrows: ["Earn"],
      title: "Revenue makes the loop real.",
      body: [
        "When an agent earns eligible stablecoin revenue, the contracts route it through the defined treasury and staking paths.",
        "The launch funds the next phase of work. Revenue shows whether the business can keep going."
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
        "Nous Hermes is the agent harness in the stack. Techtree pins what Hermes was allowed to use, evaluates the resulting episode through Prime Verifiers, and connects the receipt to the same durable agent identity."
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

  test "the public homepage never links into a route the launch gate holds", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    anchors = attribute(html, "[id]", "id")

    for href <- attribute(html, "a", "href"),
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
    assert html =~ "The economic stack for agents"

    assert has_element?(
             view,
             ".rl-hero-copy p",
             "Techtree makes the work checkable. Autolaunch turns proven edge into funding and a visible revenue path. Regent keeps the same agent operating under one identity."
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
             "Agent proof. Agent capital. Onchain revenue."
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
             "Techtree — Prove",
             "Autolaunch — Fund",
             "Earn",
             "Regent — Operate",
             "Nous — Run"
           ]
  end

  test "the proof grids stand under the two products whose surfaces they describe", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    for proof <- [
          "A proof is a set of artifacts.",
          "Proof of a declared experiment.",
          "Not every result proves the same thing.",
          "Proof graph and run list",
          "Agent-native operation",
          "Validate the task before judging the agent.",
          "The same environment can continue into training."
        ] do
      assert has_element?(view, "#techtree .rl-proof-grid article", proof)
    end

    for state <- ["Live web", "Working prototype", "In build", "Planned"] do
      assert has_element?(view, "#techtree .rl-proof-grid article .rl-proof-state", state)
    end

    for proof <- ["Private drafts", "Market discovery", "Connected reputation"] do
      assert has_element?(view, "#autolaunch .rl-proof-grid article", proof)
    end

    assert has_element?(
             view,
             "#techtree .rl-proof-grid article",
             "resolve manifests, start runs, inspect receipts, compare skills"
           )

    assert has_element?(
             view,
             "#autolaunch .rl-proof-grid article",
             "X, GitHub, Farcaster, ENS, and World"
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

    assert texts(html, "a.rl-action") == ["See how it works", "Explore the system"]
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
             "A controlled comparison people can inspect."
           )

    assert has_element?(
             view,
             "#techtree .rl-story p",
             "Hold the task membership, model, Hermes version, tools, runtime, sampling settings, and scorer fixed. Change only the declared skill. Techtree verifies that boundary, pairs results task by task, and publishes uplift, regressions, cost, latency, limitations, and evidence grade."
           )

    assert has_element?(
             view,
             "#techtree .rl-story-state",
             "The first proof starts small on purpose. The first public Techtree proof will pair a neutral baseline with a procedure skill on unseen inputs. A hidden deterministic scorer, a Prime Verifiers trace, and NVIDIA NeMo Relay trajectory evidence will expose the complete path from experiment manifest to Skill Uplift Report—not just a final score."
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
             "Uniswap handles price discovery. Safe protects custody. ERC-8004 identifies the agent. Autolaunch defines the launch, ownership, and revenue rules."
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
             "Research context, verified by primary sources."
           )

    assert has_element?(
             view,
             "#evidence .rl-evidence-note p",
             "These references explain why Techtree fixes the task, harness, runtime, scorer, and evidence boundary before claiming improvement—and why evaluation belongs inside the loop that improves an agent."
           )
  end

  test "the evidence record quotes only checked wording and labels every other entry", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, ~s(#evidence ul.rl-evidence-entries[role="list"]))

    assert has_element?(
             view,
             "#evidence .rl-evidence-entry .rl-evidence-claim",
             "Catasta’s Replit Agent work moves evaluation from a launch check into the loop that improves the agent."
           )

    assert has_element?(
             view,
             "#evidence .rl-evidence-entry .rl-evidence-claim",
             "Snowflake AI Research open-sourced data-eng-bench, a repository-level benchmark that hands an agent a live dbt project on an enterprise-scale data warehouse."
           )

    assert texts(html, "#evidence blockquote") == [
             "“We think that if people can start to build their own environments and try them out, and then we put them into leaderboards, and we figure out which ones are good and which ones are contributing to model success.”",
             "“Agentic AI is moving from ‘write code and deploy’ to ‘hypothesize, experiment, evaluate, and iterate.’ That loop doesn’t need just GPUs. It needs infrastructure, tracking, reproducibility, and memory.”"
           ]

    assert texts(html, "#evidence .rl-evidence-class") == [
             "Paraphrase",
             "Paraphrase",
             "Paraphrase",
             "Paraphrase",
             "Verified quote",
             "Paraphrase",
             "Verified quote"
           ]

    assert texts(html, "#evidence .rl-evidence-author") == [
             "Michele Catasta",
             "NVIDIA Labs",
             "Zhengyang Qi",
             "Prime Intellect",
             "Ben Burtenshaw",
             "Snowflake AI Research",
             "David Hartmann"
           ]

    assert texts(html, "#evidence .rl-evidence-affiliation") == [
             "President, Replit",
             "Agent harness research",
             "Research Scientist, Snorkel AI",
             "Environments Hub",
             "Hugging Face",
             "Data-eng-bench",
             "Lambda"
           ]
  end

  test "every primary source is an outbound link that leaves the page safely", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    sources = attribute(html, "#evidence .rl-evidence-source", "href")

    assert sources == [
             "https://replit.com/blog/evaluating-and-improving-agent-at-scale",
             "https://developer.nvidia.com/blog/six-agent-harness-capabilities-for-higher-model-performance/",
             "https://snorkel.ai/leaderboard/os-world-2-0/",
             "https://www.primeintellect.ai/blog/environments",
             "https://youtu.be/CJwn302-TBE?t=1082",
             "https://www.snowflake.com/en/blog/engineering/data-eng-bench-data-engineering-agent-benchmark/",
             "https://lambda.ai/blog/what-happens-when-claude-code-gets-an-experiment-tracker"
           ]

    assert attribute(html, ~s(a[href^="https://"]), "href") == sources

    assert attribute(html, "#evidence .rl-evidence-source", "target") ==
             List.duplicate("_blank", 7)

    assert attribute(html, "#evidence .rl-evidence-source", "rel") ==
             List.duplicate("noopener noreferrer", 7)
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
