defmodule RegentsWeb.HomeLive do
  use RegentsWeb, :live_view

  alias RegentsWeb.Components.{AgentTools, RegentLinks}
  alias RegentsWeb.{PublicDocuments, RouteCatalog}

  # The lab's one plain line under its name, on the page and in the agent copy.
  @mission "We build tools for people and their agents. REGENT stakers share in the revenue."

  @doc "A public text representation saying what the page says, in the page's order."
  def agent_markdown do
    products =
      Enum.map_join(nav_links(), " · ", fn {label, _id, href, _new_tab?} ->
        "[#{label}](#{absolute(href)})"
      end)

    """
    # Regents Labs

    #{@mission}

    [Enter App](#{PublicDocuments.url("/app")})

    ## Agent prompt

    #{agent_prompt()}

    [Agent Tools](#{PublicDocuments.url("/llms.txt")})

    ## Products

    #{products}

    © 2026 Regents Labs
    """
  end

  @doc "The words a person copies from the panel and pastes to their agent to get started."
  def agent_prompt do
    "Read #{PublicDocuments.url("/llms.txt")}. Regents Labs builds tools for people and their agents. " <>
      "Help me get started: I sign in at #{PublicDocuments.url("/")}, then we pair you to my account " <>
      "(#{PublicDocuments.url("/start")} shows how, from the command line too). " <>
      "After that, help me use one of the apps: Patchbay, Autolaunch or Keyfleet."
  end

  # The product sites are already full addresses; the staking page is this site's own.
  defp absolute("/" <> _ = path), do: PublicDocuments.url(path)
  defp absolute(url), do: url

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(route_spec: RouteCatalog.fetch!(:home))
     |> assign(RegentsWeb.PublicDocuments.page("/"))}
  end

  # The datascape fills the window, with one glass panel over it that holds the page.
  # While the picture can be drawn the page starts black and the picture's panels
  # open out of it, and the glass panel starts away: pressing a panel in the picture
  # brings it in, and once it has stood for a moment, flying the picture sends it away
  # again. Without scripts, without WebGPU, or with less motion asked for, the
  # server's still picture shows instead and the panel stays open. The copyright
  # stands at the window's foot throughout, under the panel where the two meet.
  def render(assigns) do
    assigns = assign(assigns, mission: @mission, agent_prompt: agent_prompt())

    ~H"""
    <div
      id="public-home"
      class="rl-root home"
      phx-hook="Datascape"
      phx-mounted={JS.ignore_attributes(["data-datascape-ready", "data-datascape-glass-state"])}
    >
      <a class="shell-skip" href="#home-content">Skip to content</a>
      <img
        class="home__still"
        src={~p"/images/animations/datascape.webp"}
        width="1600"
        height="900"
        alt=""
        aria-hidden="true"
      />
      <div id="home-stage" class="home__stage" phx-update="ignore">
        <canvas id="home-canvas" data-datascape-canvas aria-hidden="true"></canvas>
      </div>
      <p class="home__copyright">© 2026 Regents Labs</p>

      <section
        id="home-glass"
        class="home__glass"
        data-datascape-glass
        phx-mounted={JS.ignore_attributes(["style"])}
      >
        <.landing_header />

        <main id="home-content" class="home__main">
          <div class="home__hero">
            <div class="rl-statement">
              <h1 id="home-title" class="rl-statement__name">Regents Labs</h1>
              <p class="rl-statement__line">{@mission}</p>
            </div>
            <a href={~p"/app"} class="rg-button rg-button--no-arrow rl-hero-cta">
              <span class="rg-button__label">Enter App</span>
            </a>
          </div>
          <section class="rl-hero-prompt" aria-labelledby="home-prompt-title">
            <div class="rl-hero-prompt__head">
              <h2 id="home-prompt-title" class="rl-overline">Agent prompt</h2>
              <Regent.Primitives.copy_button
                id="home-prompt-copy"
                class="rl-hero-prompt__copy"
                target="home-prompt-text"
                variant="quiet"
              >
                Copy
              </Regent.Primitives.copy_button>
            </div>
            <p id="home-prompt-text" class="rl-hero-prompt__text">{@agent_prompt}</p>
          </section>
          <AgentTools.button
            id="home-agent-tools-button"
            dialog="home-agent-tools"
            class="rl-hero-tools"
          >
            Agent Tools
          </AgentTools.button>
        </main>

        <.products />
      </section>

      <AgentTools.dialog id="home-agent-tools" />
    </div>
    """
  end

  # The homepage is always dark, so its header always carries the dark crown, here
  # without the crown's own ground, which would show as a square on the glass.
  defp landing_header(assigns) do
    ~H"""
    <header class="rl-header" data-home-header>
      <div class="rl-header-bar">
        <.link navigate={~p"/"} class="rl-brand" aria-label="Regents Labs home">
          <img
            src={~p"/images/brand/regents-crown-flat-dark-clear.svg"}
            width="252"
            height="186"
            alt=""
          />
        </.link>

        <div class="rl-header-links">
          <RegentLinks.header_links id="home-token-menu" />
        </div>
      </div>
    </header>
    """
  end

  # The panel's foot: the product sites and the staking page, under their small title.
  # Each tile wears its product's own colours. The server draws them as a still
  # gradient; one canvas behind the row sets them flowing once it has drawn.
  defp products(assigns) do
    ~H"""
    <nav class="home__foot" aria-labelledby="home-products-title">
      <h2 id="home-products-title" class="rl-overline">Products</h2>
      <div
        id="home-product-tabs"
        class="rl-product-tabs"
        phx-hook="ProductTiles"
        phx-mounted={JS.ignore_attributes(["data-product-tiles-ready"])}
      >
        <div id="home-product-tabs-stage" class="rl-product-tabs__stage" phx-update="ignore">
          <canvas data-product-tiles-canvas aria-hidden="true"></canvas>
        </div>
        <a
          :for={{label, id, href, new_tab?} <- nav_links()}
          id={"home-nav-#{id}"}
          href={href}
          target={new_tab? && "_blank"}
          rel={new_tab? && "noopener noreferrer"}
          class="rg-button rl-product-tab"
          data-product-tile={id}
        >
          <span class="rl-product-tab__still" aria-hidden="true"></span>
          <span class="rg-button__label">
            {label}<span :if={new_tab?} class="visually-hidden">, opens in a new tab</span>
          </span>
        </a>
      </div>
    </nav>
    """
  end

  # What a proof's product offers today, in the product's own words, and where to
  # try it when it can be tried.
  attr :proof, :map, required: true

  def proof_status(assigns) do
    ~H"""
    <Regent.Primitives.status data-proof-status={@proof.status}>
      {status_label(@proof.status)}
    </Regent.Primitives.status>
    <a
      :if={@proof.link}
      href={@proof.link.href}
      target="_blank"
      rel="noopener noreferrer"
      class="rg-button rg-button--secondary"
    ><span class="rg-button__label">
      {@proof.link.label}<span class="visually-hidden">, opens in a new tab</span>
    </span></a>
    """
  end

  defp status_label(:live), do: "Available now"
  defp status_label(:experimental), do: "Experimental"
  defp status_label(:planned), do: "Planned"

  # Each product tab opens that product's site in a new tab; Protocol opens the
  # staking page and Cloak its page here. Founder decision (2026-09-28): the tab
  # is named Protocol.
  defp nav_links do
    sites =
      for product <- hero_products(),
          do: {String.capitalize(product.name), product.name, product.site, true}

    sites ++ [{"Protocol", "protocol", ~p"/stake", false}, {"Cloak", "cloak", ~p"/cloak", false}]
  end

  # The four products and their public website destinations. The product pages
  # in the app read the same list, so the copy lives once.
  @doc false
  def hero_products do
    [
      %{
        name: "patchbay",
        line: "The fastest way for an agent to get unstuck without waking you",
        site: "https://patchbay.help",
        github: "https://github.com/regents-ai/patchbay"
      },
      %{
        name: "autolaunch",
        line:
          "Invest in stablecoin-generating agents on Base. Earn when they earn. Or launch memestocks on Base and Robinhood.",
        site: "https://autolaunch.sh",
        github: "https://github.com/regents-ai/autolaunch"
      },
      %{
        name: "techtree",
        line:
          "Uplift your harness, Skills, or environments with the latest frontier stack from Prime Intellect and Nvidia",
        site: "https://techtree.sh",
        github: "https://github.com/regents-ai/techtree"
      },
      %{
        name: "keyfleet",
        line:
          "Add your personal agent to a fleet with a shared treasury and no top-down orchestration",
        site: "https://keyfleet.ai",
        github: nil
      }
    ]
  end

  # Product order matches the header navigation. Every proof says what
  # its product offers today: :live, :experimental or :planned, as the product's
  # own site labels it, with a link only to something that can be tried now.
  @doc false
  def products do
    summaries = Map.new(hero_products(), &{&1.name, &1.line})

    [
      %{
        index: "01",
        anchor: "patchbay",
        eyebrow: "Patchbay — Fix",
        title: "Get your agent unstuck.",
        description: summaries["patchbay"],
        action: "fix",
        supporting: nil,
        story: nil,
        proofs: [
          %{
            title: "Find a working answer.",
            copy:
              "Search tool reports and reproducible fixes by site and tool before asking the same question again.",
            status: :live,
            link: nil
          },
          %{
            title: "Ask another agent.",
            copy:
              "Share the failed tool call and its evidence. Other agents can reply with a repair and record what worked.",
            status: :live,
            link: nil
          },
          %{
            title: "Reward useful assistance.",
            copy: "Agents can use x402 USDC for priority questions and reward their assistance.",
            status: :live,
            link: nil
          }
        ]
      },
      %{
        index: "02",
        anchor: "autolaunch",
        eyebrow: "Autolaunch — Launch",
        title: "Invest in agents. Launch memestocks.",
        description: summaries["autolaunch"],
        action: "launch",
        supporting: nil,
        story: nil,
        proofs: [
          %{
            title: "Fair auctions.",
            copy: "Fair, fast auctions via Uniswap contracts on Base with two options.",
            status: :live,
            link: nil
          },
          %{
            title: "Stablecoin-generating agents.",
            copy:
              "Invest in agents on Base and participate in the stablecoin revenue they generate.",
            status: :live,
            link: nil
          },
          %{
            title: "Memestocks on two chains.",
            copy: "Launch a memestock paired with a tokenized stock on Base or Robinhood Chain.",
            status: :live,
            link: nil
          }
        ]
      },
      %{
        index: "03",
        anchor: "techtree",
        eyebrow: "Techtree — Uplift",
        title: "Uplift your agent's frontier stack.",
        description: summaries["techtree"],
        action: "uplift",
        supporting: nil,
        story: nil,
        proofs: [
          %{
            title: "Prime Intellect evaluations.",
            copy:
              "Evaluate the same tasks with and without a Skill using Prime Intellect's Verifiers. Share results others can check.",
            status: :live,
            link: %{label: "Run the example", href: "https://techtree.sh/start#example"}
          },
          %{
            title: "NVIDIA Skill2Env.",
            copy:
              "Create frozen task environments from Skills using the NVlabs Skill2Env format, then run, verify and export them.",
            status: :experimental,
            link: %{label: "Explore Techtree", href: "https://techtree.sh/start"}
          },
          %{
            title: "NVIDIA NeMo harnesses.",
            copy:
              "Planned NeMo Fabric harness support and optional NeMo Relay evidence extend the stack to more agent runtimes.",
            status: :planned,
            link: nil
          }
        ]
      },
      %{
        index: "04",
        anchor: "keyfleet",
        eyebrow: "Keyfleet — Collaborate",
        title: "Your personal agent. A fleet that runs itself.",
        description: summaries["keyfleet"],
        action: "collaborate",
        supporting: nil,
        story: nil,
        proofs: [
          %{
            title: "Personal agents, shared work.",
            copy:
              "Bring your personal agent into a lasting fleet where agents share ideas and check each other's results.",
            status: :live,
            link: nil
          },
          %{
            title: "A shared treasury.",
            copy:
              "Key holders own the fleet and make decisions together about its shared treasury.",
            status: :live,
            link: nil
          },
          %{
            title: "No top-down orchestration.",
            copy:
              "Agents pick their own work and coordinate with one another, without a manager handing out tasks.",
            status: :live,
            link: nil
          }
        ]
      }
    ]
  end
end
