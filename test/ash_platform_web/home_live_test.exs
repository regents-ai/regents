defmodule AshPlatformWeb.HomeLiveTest do
  use AshPlatformWeb.ConnCase, async: true

  # Nous is the runtime the products run on, not a Regents product: it has no chapter of its own.
  @chapters ~w(techtree autolaunch patchbay)

  # The three products the hero lists, in the founder's order, with his one-liners. Only
  # techtree has a site to open today; the other two say so on a control that does nothing.
  @hero_products [
    %{
      name: "autolaunch",
      line: "Agents raise funds through CCA auctions on Base. Earn when they earn.",
      site: "https://autolaunch.sh",
      github: "https://github.com/regents-ai/autolaunch",
      open: false
    },
    %{
      name: "techtree",
      line:
        "Upgrade your agent with proven skill, harness, and env improvements. Buy and sell upgrades with other agents.",
      site: "https://techtree.sh",
      github: "https://github.com/regents-ai/techtree",
      open: true
    },
    %{
      name: "patchbay",
      line:
        "Collaborative WebMCP forum for troubleshooting Tool calling issues. Agents help agents.",
      site: "https://patchbay.help",
      github: "https://github.com/regents-ai/patchbay",
      open: false
    }
  ]

  @nav [
    {"techtree", "Techtree", "#techtree"},
    {"autolaunch", "Autolaunch", "#autolaunch"},
    {"patchbay", "Patchbay", "#patchbay"},
    {"about", "About", "#home-closing"}
  ]

  # Prove, fund, earn, operate, run: revenue follows the launch that produces it, and Nous closes
  # the product story as the runtime the three products run on.
  @sections ~w(techtree autolaunch revenue patchbay nous home-closing)

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
      anchor: "patchbay",
      eyebrows: ["Patchbay — Repair"],
      title: "Agents help agents fix broken tools.",
      body: [
        "Patchbay is a working prototype of a board where an agent reports one of Patchbay's own tools that misbehaved and quotes the proof it was handed. Patchbay checks that proof against its own record of the call, works out a repair within a fixed set of allowed changes, tries it, and publishes the fix."
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

  test "the header indexes the page and the hero lists every product", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#public-home[phx-hook=HomeHero]")
    assert has_element?(view, "[data-home-header]")
    assert has_element?(view, "[data-home-hero-copy]")
    assert has_element?(view, "ul#home-products[data-home-hero-cards]")

    for {slug, label, target} <- @nav do
      assert has_element?(view, "#home-nav-#{slug}[href=\"#{target}\"]", label)
    end

    for anchor <- @chapters do
      assert has_element?(view, "##{anchor}.rl-chapter")
    end

    # Each card names itself, which is how pointing at one tells the hero what to become.
    assert attribute(html, "[data-home-hero-card]", "data-home-hero-card") ==
             Enum.map(@hero_products, & &1.name)

    assert length(Regex.scan(~r/<section id="(?:techtree|autolaunch|patchbay)"/, html)) == 3
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
    assert has_element?(view, ~s(.rl-header-links a[href="/stake"]), "App")
    refute has_element?(view, "a.rl-action--disabled")
  end

  test "the hero names the company, what it is, and what it makes", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "h1#home-title", "Regents Labs")

    # The capitals are the stylesheet's doing; the sentence itself is written once, plainly.
    assert texts(html, ".rl-hero-copy p") == [
             "A no-equity company with onchain revenue split"
           ]

    # The visible label above the cards is the list's own name, so it is not invented twice.
    assert has_element?(view, "p#home-products-label", "Agentic Products")
    assert attribute(html, "ul#home-products", "aria-labelledby") == ["home-products-label"]
    assert attribute(html, "ul#home-products", "aria-label") == []
  end

  test "each product card carries the founder's line and its two controls", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert texts(html, "[data-home-hero-card] strong") == Enum.map(@hero_products, & &1.name)
    assert texts(html, "[data-home-hero-card] > p") == Enum.map(@hero_products, & &1.line)

    for product <- @hero_products do
      card = "#home-card-#{product.name}"

      if product.open do
        assert has_element?(
                 view,
                 ~s(#{card} .rl-card-actions a.rl-action[href="#{product.site}"][target="_blank"][rel="noopener noreferrer"]),
                 "Open #{product.name} ↗"
               )
      else
        # A site that is not open yet keeps its place on a control that really does nothing.
        assert has_element?(
                 view,
                 ~s(#{card} .rl-card-actions button.rl-action[type="button"][disabled][aria-disabled="true"]),
                 "Open #{product.name} ↗"
               )

        assert attribute(html, "#{card} .rl-card-actions a.rl-action", "href") == []
      end

      assert has_element?(
               view,
               ~s(#{card} a.rl-card-source[href="#{product.github}"][target="_blank"][rel="noopener noreferrer"][aria-label="#{product.name} on GitHub"])
             )
    end

    assert attribute(html, "[data-home-hero-card] a.rl-card-source", "href") ==
             Enum.map(@hero_products, & &1.github)
  end

  test "the hero closes on what staking pays and the two ways to take part", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert sentences(html, ".rl-hero-stakers > p") == [
             "Regents Labs is unique in that REGENT token stakers receive a pro rata split of all USDC revenue"
           ]

    # Buying happens on Uniswap and the chart lives on DexScreener, and both
    # name the token this page reports on.
    assert has_element?(
             view,
             ~s(.rl-stakers-actions a.rl-action[href="https://app.uniswap.org/explore/tokens/base/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07"][target="_blank"][rel="noopener noreferrer"]),
             "Buy REGENT ↗"
           )

    assert has_element?(
             view,
             ~s(.rl-stakers-actions a.rl-action[href^="https://dexscreener.com/"][target="_blank"][rel="noopener noreferrer"]),
             "View Chart ↗"
           )

    # Staking is ours, so it opens where the visitor already is.
    assert has_element?(view, ~s(.rl-stakers-actions a.rl-action[href="/stake"]), "Stake REGENT")
    assert attribute(html, ~s(.rl-stakers-actions a[href="/stake"]), "target") == []
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
             "Regents Labs builds Techtree, Autolaunch and Patchbay."
           )

    assert has_element?(
             view,
             ".rl-footer .rl-footer-brand span",
             "Agent proof. Agent runway. Onchain revenue."
           )

    assert has_element?(view, ".rl-footer p", "© 2026 Regents Labs")
    assert attribute(html, ".rl-footer a", "href") == []
  end

  test "the cards stand in the founder's order", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert attribute(html, "[data-home-hero-card]", "id") ==
             Enum.map(@hero_products, &"home-card-#{&1.name}")
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
             "Patchbay — Repair",
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

    assert texts(html, "#patchbay .rl-proof-grid article h3") == [
             "A report carries its own proof.",
             "The repair happens on its own.",
             "The open page keeps up."
           ]

    # Patchbay claims no more than Techtree does, and wears the same label for it.
    assert texts(html, "#patchbay .rl-proof-grid article .rl-proof-state") ==
             ["Working prototype", "Working prototype", "Working prototype"]

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

    refute html =~ "partners"
    refute html =~ "customers"
  end

  # The hero art is the picture the server promises. The crown and the field of squares
  # are two decorative canvases the browser may put behind it, and nothing else: they
  # carry no copy, take no focus, send nothing back, and cannot come between a visitor
  # and an action.
  test "the page carries two inert, client-owned decorations", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(.rl-hero > #home-prism.rl-hero-prism[phx-hook="HomePrism"][phx-update="ignore"][aria-hidden="true"])
           )

    assert has_element?(
             view,
             ~s(#public-home > #home-field.rl-home-field[phx-hook="HomeField"][phx-update="ignore"][aria-hidden="true"])
           )

    assert has_element?(view, ~s(.rl-hero > .rl-hero-copy[data-home-hero-copy] h1#home-title))

    assert attribute(html, "#home-prism canvas", "data-home-prism-canvas") == [""]
    assert attribute(html, "#home-field canvas", "data-home-field-canvas") == [""]

    for island <- ~w(#home-prism #home-field) do
      assert attribute(html, "#{island} canvas", "tabindex") == []
      assert texts(html, island) == [""]
      assert attribute(html, "#{island} a, #{island} button", "id") == []
    end

    for reactive <- ~w(phx-click phx-change phx-submit phx-value data-prism-ready) do
      assert attribute(html, "#home-prism", reactive) == []
    end

    for reactive <- ~w(phx-click phx-change phx-submit phx-value data-field-ready) do
      assert attribute(html, "#home-field", reactive) == []
    end
  end

  test "the page offers only the actions the copy promises", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert texts(html, "a.rl-action") == [
             "App",
             "Open techtree ↗",
             "Buy REGENT ↗",
             "View Chart ↗",
             "Stake REGENT",
             "Patchbay on GitHub ↗",
             "Explore the system"
           ]

    assert texts(html, "button.rl-action") == ["Open autolaunch ↗", "Open patchbay ↗"]

    # One primary action, on the only beat that asks for something: start again.
    assert texts(html, ".rl-action--strong") == ["Explore the system"]
    assert texts(html, "#home-closing .rl-action--strong") == ["Explore the system"]
  end

  test "the landing is one document for everyone and declares the dark it paints", %{conn: conn} do
    landing = fn theme ->
      conn
      |> Plug.Test.put_req_cookie("regent_theme", theme)
      |> get("/")
      |> html_response(200)
    end

    plain = conn |> get("/") |> html_response(200)
    light = landing.("light")
    dark = landing.("dark")

    assert stable_render(light) == stable_render(plain)
    assert stable_render(dark) == stable_render(plain)

    for html <- [plain, light, dark] do
      assert attribute(html, "html", "data-theme") == ["dark"]
      assert attribute(html, "meta[name=color-scheme]", "content") == ["dark"]
    end
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

  # Patchbay's own site is not open to visitors yet, so the chapter offers its source and
  # nothing else, and that one control has to keep its exact identity and destination.
  test "the Patchbay chapter points at its source and nowhere else", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(#patchbay a#patchbay-source.rl-action[href="https://github.com/regents-ai/patchbay"][target="_blank"][rel="noopener noreferrer"]),
             "Patchbay on GitHub ↗"
           )

    refute has_element?(view, "#patchbay-source.rl-action--strong")

    assert attribute(html, "#patchbay .rl-chapter-actions a", "href") == [
             "https://github.com/regents-ai/patchbay"
           ]
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

  # Everything a landing render is allowed to differ by: the CSRF token and the
  # LiveView handshake, all minted per request.
  defp stable_render(html) do
    html
    |> String.replace(~r/csrf-token" content="[^"]*"/, ~s(csrf-token" content="TOKEN"))
    |> String.replace(~r/data-phx-session="[^"]*"/, ~s(data-phx-session="SESSION"))
    |> String.replace(~r/data-phx-static="[^"]*"/, ~s(data-phx-static="STATIC"))
    |> String.replace(~r/id="phx-[^"]*"/, ~s(id="ID"))
  end

  # The server may wrap a long sentence across source lines; a browser reads it as one.
  defp sentences(html, selector),
    do: html |> texts(selector) |> Enum.map(&(&1 |> String.split() |> Enum.join(" ")))

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp texts(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end
end
