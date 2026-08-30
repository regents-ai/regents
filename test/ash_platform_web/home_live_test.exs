defmodule AshPlatformWeb.HomeLiveTest do
  use AshPlatformWeb.ConnCase, async: true

  # Nous is the runtime the products run on, not a Regents product: it has no tile and no number.
  @products [
    {"techtree", "Techtree", "Prove what makes an agent better."},
    {"autolaunch", "Autolaunch", "Turn proven edge into runway."},
    {"regent", "Regent", "Designed for use by Hermes agents."}
  ]

  @nav [
    {"techtree", "Techtree", "#techtree"},
    {"autolaunch", "Autolaunch", "#autolaunch"},
    {"regent", "Regent", "#regent"},
    {"about", "About", "#home-closing"}
  ]

  # Prove, fund, earn, operate, run: revenue follows the launch that produces it, and Nous closes
  # the product story as the runtime the three products run on.
  @sections ~w(techtree autolaunch revenue regent nous home-closing)

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
      title: "Designed for use by Hermes agents.",
      body: [
        "Nous Portal is the fastest way to create an always-on agent to be used with Techtree and Autolaunch."
      ]
    },
    %{
      anchor: "nous",
      eyebrows: ["Nous — Run"],
      title: "Hermes performs the work.",
      body: [
        "Hermes Agent is the agent harness in the stack. Techtree pins what Hermes was allowed to use, evaluates the resulting episode through Prime Verifiers, and connects the receipt to the same durable agent identity."
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
      assert href == "/stake" or String.starts_with?(href, "#")
      if String.starts_with?(href, "#"), do: assert(String.trim_leading(href, "#") in anchors)
    end
  end

  test "every header control names a real destination", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, ~s(.rl-brand[href="/"]), "Regents Labs")
    refute has_element?(view, ".rl-header-note")

    assert attribute(html, ".rl-header a", "href") ==
             ["/" | Enum.map(@nav, &elem(&1, 2))] ++
               ["https://x.com/regents_sh", "https://github.com/regents-ai", "/stake"]

    assert has_element?(view, ~s(.rl-header-links a[aria-label="Regents on X"]))
    assert has_element?(view, ~s(.rl-header-links a[aria-label="Regents on GitHub"]))
    assert has_element?(view, ~s(.rl-header-links a[href="/stake"]), "Stake REGENT")
    refute has_element?(view, "a.rl-action--disabled")
  end

  test "the hero states the stack and offers one in-page way into it", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "h1#home-title", "Prove the edge. Fund the agent.")
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
             "Proof strength is explicit."
           ]

    assert texts(html, "#techtree .rl-proof-grid article .rl-proof-state") == [
             "Working prototype",
             "Working prototype",
             "Working prototype"
           ]

    for proof <- ["Private drafts", "Market discovery", "Connected reputation"] do
      assert has_element?(view, "#autolaunch .rl-proof-grid article", proof)
    end

    assert texts(html, "#autolaunch .rl-proof-grid article .rl-proof-state") ==
             ["Live", "Preview", "Preview"]

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

  # The hero art is the picture the server promises. The prism is one decorative canvas
  # the browser may put in front of it, and nothing else: it carries no copy, takes no
  # focus, sends nothing back, and cannot come between a visitor and an action.
  test "the hero art carries one inert, client-owned decoration", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(.rl-hero > #home-prism.rl-hero-prism[phx-hook="HomePrism"][phx-update="ignore"][aria-hidden="true"])
           )

    assert attribute(html, "#home-prism canvas", "data-home-prism-canvas") == [""]
    assert attribute(html, "#home-prism canvas", "tabindex") == []
    assert texts(html, "#home-prism") == [""]
    assert attribute(html, "#home-prism a, #home-prism button", "id") == []

    for reactive <- ~w(phx-click phx-change phx-submit phx-value data-prism-ready) do
      assert attribute(html, "#home-prism", reactive) == []
    end
  end

  test "the page offers only the actions the copy promises", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert texts(html, "a.rl-action") == [
             "Stake REGENT",
             "See how it works",
             "Create Agent on Nous",
             "Explore the system"
           ]

    assert texts(html, "button.rl-action") == ["Copy Instructions to My Hermes"]

    # Three primary actions, one per beat: enter the story, create the agent, start again.
    assert texts(html, ".rl-hero-actions .rl-action--strong") == ["See how it works"]
    assert texts(html, "#regent .rl-action--strong") == ["Create Agent on Nous"]
    assert texts(html, "#home-closing .rl-action--strong") == ["Explore the system"]
    assert length(texts(html, ".rl-action--strong")) == 3
  end

  test "the homepage stays outside the application shell and within its HTML budget", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    refute html =~ ~s(id="app-shell")
    assert byte_size(html) <= 20 * 1024
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

  # The Regent chapter hands an operator to Nous and hands their agent its own instructions, so
  # both controls have to keep their exact identity, destination, and payload.
  test "the Regent chapter offers a safe Nous handoff beside a native copy control", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(#regent a#regent-create-agent.rl-action--strong[href="https://portal.nousresearch.com/"][target="_blank"][rel="noopener noreferrer"]),
             "Create Agent on Nous"
           )

    assert has_element?(
             view,
             ~s(#regent button#regent-copy-hermes-instructions.rl-action[type="button"]),
             "Copy Instructions to My Hermes"
           )

    refute has_element?(view, "#regent-copy-hermes-instructions.rl-action--strong")

    assert attribute(html, "#regent-copy-hermes-instructions", "data-copy-hermes-instructions") ==
             [
               "Help me use Techtree and Autolaunch with this Hermes agent. Check which Regent tools and skills are available, then guide me through the next step."
             ]

    assert has_element?(
             view,
             ~s(#regent p#regent-copy-status[role="status"][aria-live="polite"])
           )

    assert texts(html, "#regent-copy-status") == [""]
  end

  # The founder copy this page dropped lives in docs/copy-for-later-use.md and nowhere else: no
  # rendered trace of the evidence section, the expanded proof grid, or the benchmark summary.
  test "the archived founder copy is absent from the rendered page", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    for anchor <- ~w(evidence product-summary) do
      refute has_element?(view, "##{anchor}")
    end

    for archived <- [
          "Built on open systems with distinct jobs.",
          "Evals + RL Environment Recent Quotes",
          "Techtree proof is not a financial promise",
          "Public Climbs and proof graph",
          "Qualified evidence can continue into training",
          "Install the Techtree CLI",
          "Run a private Verify",
          "From benchmark to business.",
          "Keep the agent working.",
          "Humans get a guided path.",
          "Michele Catasta",
          "youtube.com",
          "/images/brand/quotes/"
        ] do
      refute html =~ archived
    end
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
