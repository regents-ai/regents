defmodule AshPlatformWeb.HomeLiveTest do
  use AshPlatformWeb.ConnCase, async: true

  @products [
    {"formation", "formation", "Formation"},
    {"autolaunch", "autolaunch", "Autolaunch"},
    {"techtree", "techtree", "Techtree"},
    {"regents-labs", "regent", "Regents Labs"}
  ]

  @nav [
    {"techtree", "Techtree", "#techtree"},
    {"autolaunch", "Autolaunch", "#autolaunch"},
    {"regent", "Regent", "#regents-labs"},
    {"about", "About", "#home-closing"}
  ]

  # The sourced evidence follows the Techtree chapter it stands behind.
  @sections ~w(formation autolaunch techtree evidence regents-labs home-closing)

  test "the header indexes the page and the bento reaches every chapter", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#public-home[phx-hook=HomeHero]")
    assert has_element?(view, "[data-home-header]")
    assert has_element?(view, "[data-home-hero-copy]")
    assert has_element?(view, "#home-products[data-home-hero-cards]")

    for {slug, label, target} <- @nav do
      assert has_element?(view, "#home-nav-#{slug}[href=\"#{target}\"]", label)
    end

    for {anchor, card_key, label} <- @products do
      assert has_element?(
               view,
               "#home-card-#{card_key}[data-home-hero-card][href=\"##{anchor}\"]",
               label
             )

      assert has_element?(view, "##{anchor}.rl-chapter")
    end

    assert length(Regex.scan(~r/data-home-hero-card=""/, html)) == 4

    assert length(
             Regex.scan(~r/<section id="(?:formation|autolaunch|techtree|regents-labs)"/, html)
           ) == 4
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

  test "the hero bento leads with Techtree and places Autolaunch second", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert attribute(html, "[data-home-hero-card]", "id") ==
             ~w(home-card-techtree home-card-autolaunch home-card-formation home-card-regent)
  end

  test "Formation copy claims only the Nous Portal route to a cloud runtime", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#home-card-formation", "Run your Regent in Nous Portal.")
    assert html =~ "Nous Portal is where you create and manage your Regent’s cloud runtime."
    assert has_element?(view, "#formation .rl-proof-grid article", "Open Nous Portal")
    assert has_element?(view, "#formation .rl-proof-grid article", "Your session stays open")

    for provisioning_claim <- ["One active Regent", "Provision", "private cloud"] do
      refute html =~ provisioning_claim
    end
  end

  test "each marketing chapter has a labelled heading and its proofs", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    for {anchor, _card_key, _label} <- @products do
      assert has_element?(
               view,
               "section##{anchor}[aria-labelledby=\"#{anchor}-title\"] h2##{anchor}-title"
             )
    end

    assert html =~ "Formation / Live"
    assert html =~ "Autolaunch / Preview"
    assert html =~ "Techtree — Prove"
    assert html =~ "Regents Labs / Live"

    for proof <- [
          "Map and List",
          "Evidence you can check",
          "Notebooks on your device",
          "Signed-in discussion",
          "Agent participation"
        ] do
      assert has_element?(view, "#techtree .rl-proof-grid article", proof)
    end

    assert html =~ "publish evidence through Regents CLI"
    assert html =~ "node creation stays read-only here"
  end

  test "the hero preserves the approved art and readable server content", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(img.rl-hero-art[src="/images/home/hero-bg-dark.svg"][loading="eager"])
           )

    assert html =~ "Build public signal before launch."
    assert html =~ "Turn agent runs into public, checkable proof."
    assert html =~ "Keep identity and value actions together."
    assert html =~ "X, GitHub, Farcaster, ENS, and World"
    assert length(Regex.scan(~r/data-home-voxel=""/, html)) == 24

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

    assert has_element?(view, "#techtree .rl-overline", "Techtree — Prove")

    assert has_element?(
             view,
             "h2#techtree-title",
             "Turn agent runs into public, checkable proof."
           )

    assert has_element?(
             view,
             "#techtree .rl-chapter-intro div > p",
             "Techtree keeps the task, model, agent, runtime, skill version, result, and limits together. Readers can see what changed, what improved, and how strong the evidence is."
           )

    assert has_element?(
             view,
             "#techtree .rl-chapter-support",
             "Prime Verifiers runs the evaluation. Nous Hermes is the agent. Techtree records the evidence, identity, and lineage."
           )

    assert has_element?(view, "#techtree .rl-story h3", "A result people can inspect.")

    assert has_element?(
             view,
             "#techtree .rl-story p",
             "Hold the model, tasks, runtime, and permissions fixed. Change one skill. Publish the before-and-after result with its cost, limitations, and evidence level."
           )

    assert has_element?(
             view,
             "#techtree .rl-story-state",
             "The first public Techtree proof is being prepared. It will show the full evaluation setup, result, limitations, and evidence class—not just a final score."
           )
  end

  test "the evidence section states both claim rails and their source labels", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(section#evidence[aria-labelledby="evidence-title"] h2#evidence-title),
             "Built on systems you can inspect."
           )

    assert has_element?(
             view,
             "#evidence .rl-evidence-intro p",
             "Every technical claim on this page should link to the primary source, deployed contract, or public receipt that supports it."
           )

    assert texts(html, "#evidence .rl-evidence-rail h3") ==
             ["Evaluation you can trace.", "Rules enforced onchain."]

    assert has_element?(
             view,
             "#evidence .rl-evidence-rail p",
             "Prime Verifiers runs the experiment. Nous Hermes operates the agent. Techtree binds the result to identity, evidence, and lineage."
           )

    assert has_element?(
             view,
             "#evidence .rl-evidence-rail p",
             "Uniswap handles price discovery. Safe protects custody. ERC-8004 identifies the agent. Autolaunch defines the launch, ownership, and revenue rules."
           )

    assert texts(html, "#evidence .rl-evidence-sources") == [
             "Prime Intellect · Nous Research · Public Techtree receipt",
             "Uniswap · Safe · ERC-8004 · Deployed contract manifest"
           ]

    assert has_element?(view, "#evidence .rl-evidence-note", "Verified by primary sources.")
  end

  test "the evidence record quotes only checked wording and labels every other entry", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

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
             "Agent World Model",
             "Lambda"
           ]

    assert attribute(html, "#evidence .rl-evidence-entry", "data-evidence-rail") ==
             List.duplicate("evaluation-and-harnesses", 3) ++
               List.duplicate("environments-and-experimentation", 4)
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
             "https://github.com/Snowflake-Labs/agent-world-model",
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
