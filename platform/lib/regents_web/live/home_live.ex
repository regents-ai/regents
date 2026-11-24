defmodule RegentsWeb.HomeLive do
  @moduledoc """
  Regents Labs marketing homepage (`/`): Stripe-style solid inverse top bar,
  full-viewport dark Datascape vgpu island hero (cursor-navigable infinite canvas
  that reveals the center hero area on first click and morphs clicked shapes into
  new random shapes on subsequent clicks), Products, Agents with the WebMCP
  modal dialog, `$REGENT`, Reading, closing band, and huge `Regents` footer.
  """

  use RegentsWeb, :live_view

  alias Phoenix.LiveView.JS
  alias RegentsWeb.Components.{AgentTools, Marketing, ValueCards}
  alias RegentsWeb.Live.Session
  alias RegentsWeb.{PublicDocuments, RegentOpsLive, RouteCatalog}
  alias RegentsWeb.Stake.TokenLinks

  @mission "We build platforms for persistent agents. All revenue is converted to USDC and split with $REGENT stakers."
  @mission_note "Agent-built and designed to be agent-owned through the token."

  @doc "A public text representation saying what the page says, in the page's order."
  def agent_markdown do
    products =
      Enum.map_join(RegentOpsLive.products(), "\n\n", fn product ->
        "### #{product.name}\n\n#{product.headline} #{product.line}\n\n" <>
          "[#{product.action}](#{PublicDocuments.url(product.href)})"
      end)

    """
    # Regents Labs

    #{@mission}

    #{@mission_note}

    [Enter App](#{PublicDocuments.url("/app")})

    [Agent Tools](#{PublicDocuments.url("/llms.txt")})

    ## Agent prompt

    #{agent_prompt()}

    ## Products

    #{products}

    ## $REGENT

    #{TokenLinks.address()}

    [Buy on Uniswap](#{TokenLinks.buy()}) · [View Chart](#{TokenLinks.chart()})

    ## Public resources

    - Developer docs: #{PublicDocuments.url("/docs")}
    - OpenAPI specification: #{PublicDocuments.url("/openapi.json")}
    - RFC 9727 API catalog: #{PublicDocuments.url("/.well-known/api-catalog")}
    - Official CLI (PyPI): https://pypi.org/project/regents-cli/
    - Hosted MCP server: #{PublicDocuments.url("/mcp")}
    - MCP server card: #{PublicDocuments.url("/mcp/server-card")}
    - AI Catalog: #{PublicDocuments.url("/.well-known/ai-catalog.json")}
    - MCP Registry manifest: #{PublicDocuments.url("/server.json")}
    - Agent Skills index: #{PublicDocuments.url("/.well-known/agent-skills/index.json")}
    - Pricing: #{PublicDocuments.url("/pricing.md")}
    - Machine-readable site guide: #{PublicDocuments.url("/llms.txt")}
    - Sitemap: #{PublicDocuments.url("/sitemap.xml")}

    © 2026 Regents Labs
    """
  end

  @doc "The words a person copies from the panel and pastes to their agent to get started."
  def agent_prompt do
    "Read #{PublicDocuments.url("/llms.txt")}. Regents Labs builds platforms for persistent agents. " <>
      "Help me get started: I sign in at #{PublicDocuments.url("/")}, then we pair you to my account " <>
      "(#{PublicDocuments.url("/start")} shows how, from the command line too). " <>
      "After that, help me use one of the apps: Patchbay, Autolaunch or Keyfleet."
  end

  @impl true
  def mount(_params, session, socket) do
    tools = AgentTools.tools()

    preview_tools =
      tools
      |> Enum.take(4)
      |> Enum.with_index(1)
      |> Enum.map(fn {tool, idx} ->
        Map.put(tool, :index, String.pad_leading(Integer.to_string(idx), 2, "0"))
      end)

    {cloak, others} = Enum.split_with(RegentOpsLive.products(), &(&1.name == "Cloak"))
    {primary_products, secondary_products} = Enum.split(cloak ++ others, 4)

    {:ok,
     socket
     |> assign(route_spec: RouteCatalog.fetch!(:home))
     |> assign(account_control: Session.account_control(session))
     |> assign(
       agent_prompt: agent_prompt(),
       tool_count: length(tools),
       preview_tools: preview_tools,
       primary_products: primary_products,
       secondary_products: secondary_products,
       buy_url: TokenLinks.buy(),
       chart_url: TokenLinks.chart()
     )
     |> assign(PublicDocuments.page("/"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="marketing-home" data-marketing-page phx-hook="MarketingPage">
      <Marketing.symbols />
      <a class="skip" href="#main">Skip to content</a>

      <Marketing.bar current="regents" over_hero />
      <Marketing.sheet />

      <main id="main">
        <section
          class="hero"
          id="home-hero"
          data-hero-section
          phx-hook="DatascapeHero"
          aria-labelledby="hero-title"
        >
          <div
            id="datascape-stage"
            class="hero__stage"
            data-datascape
            phx-update="ignore"
            phx-mounted={JS.ignore_attributes(["data-datascape-ready", "data-datascape-dragging"])}
          >
            <picture class="hero__ground">
              <source
                media="(max-aspect-ratio: 4/5)"
                srcset="/images/marketing/datascape-tall.webp"
                width="780"
                height="1688"
              />
              <img
                class="hero__still"
                src="/images/marketing/datascape.webp"
                alt=""
                width="1600"
                height="900"
              />
            </picture>
            <picture class="hero__ground hero__ground--crown">
              <source
                media="(max-aspect-ratio: 4/5)"
                srcset="/images/marketing/datascape-crown-tall.webp"
                width="780"
                height="1688"
              />
              <img
                class="hero__still"
                src="/images/marketing/datascape-crown.webp"
                alt=""
                width="1600"
                height="900"
                loading="lazy"
              />
            </picture>
            <canvas class="hero__canvas" data-datascape-canvas aria-hidden="true"></canvas>
          </div>
          <div class="hero__crown" aria-hidden="true">
            <svg><use href="#mark-crown" /></svg>
          </div>
          <div class="hero__mark" data-crown aria-hidden="true">
            <img
              class="hero__mark-still"
              src="/images/marketing/crown.webp"
              alt=""
              width="1244"
              height="841"
              loading="lazy"
            />
          </div>
          <div class="hero__words">
            <p class="hero__label label">Regents Labs</p>
            <h1 class="hero__title" id="hero-title">Agent-native</h1>
            <p class="hero__sentence">
              A product lab that builds what agents use themselves. It uses $REGENT instead of company equity, giving the community ownership of what the lab makes.
            </p>
            <div class="hero__actions actions">
              <Marketing.cta_button label="Enter App" href="/app" />
              <button
                class="btn btn--secondary"
                type="button"
                aria-haspopup="dialog"
                aria-controls="tools"
                data-window-open
              >
                Agent Tools
              </button>
            </div>
          </div>
          <a
            id="hero-scroll-cue"
            href="#products"
            class="hero__scroll"
            aria-label="Scroll to Products"
            phx-hook="HeroChevron"
            phx-mounted={JS.ignore_attributes(["data-hero-chevron-ready"])}
          >
            <span class="hero__scroll-inner" aria-hidden="true">
              <Regent.Icons.icon name="chevrons-down" class="hero__scroll-still" />
              <span id="hero-scroll-stage" class="hero__scroll-stage" phx-update="ignore">
                <canvas class="hero__scroll-canvas" data-hero-chevron-canvas></canvas>
              </span>
            </span>
          </a>
        </section>

        <div class="frame">
          <section class="section" id="products" aria-labelledby="products-title">
            <div class="shead">
              <h2 class="shead__title" id="products-title">Products</h2>
            </div>
            <div class="home-products-grid">
              <ValueCards.value_cards
                id="home-products"
                label="Products"
                cards={@primary_products}
              />
            </div>
            <div class="home-ecosystem-grid">
              <ValueCards.value_cards
                id="home-ecosystem"
                label="Protocol and tools"
                cards={@secondary_products}
              />
            </div>
          </section>

          <section class="section" id="agents" aria-labelledby="agents-title">
            <div class="split">
              <div class="shead">
                <h2 class="shead__title" id="agents-title">Agents</h2>
                <p class="shead__lede">Give your agent one of these.</p>
                <div class="shead__links">
                  <a class="go" href="/agents.md">
                    Setup steps <svg class="icon" aria-hidden="true"><use href="#icon-next" /></svg>
                  </a>
                  <a class="go" href="/llms.txt">
                    Site summary <svg class="icon" aria-hidden="true"><use href="#icon-next" /></svg>
                  </a>
                  <a class="go" href="/docs">
                    Developer docs
                    <svg class="icon" aria-hidden="true"><use href="#icon-next" /></svg>
                  </a>
                </div>
              </div>
              <div class="prompt">
                <div class="prompt__head">
                  <p class="label">Agent prompt</p>
                  <button class="copy" type="button" data-copy-from="agent-prompt">
                    <svg class="icon" aria-hidden="true"><use href="#icon-copy" /></svg>
                    <span class="copy__words">
                      <span class="copy__idle">Copy</span>
                      <span class="copy__done">Copied</span>
                      <span class="copy__failed">Couldn't copy</span>
                    </span>
                  </button>
                </div>
                <p class="prompt__text" id="agent-prompt">{@agent_prompt}</p>
              </div>
            </div>

            <div class="subhead" id="agent-tools">
              <h3 class="subhead__title">Agent Tools</h3>
              <p class="label muted">{@tool_count} WebMCP Tools</p>
            </div>
            <ol class="steps">
              <li :for={tool <- @preview_tools} class="step">
                <span class="step__index">{tool.index}</span>
                <h4 class="step__title">{tool.title}</h4>
                <p class="step__line"><code>{tool.name}</code></p>
              </li>
            </ol>
            <div class="actions actions--after">
              <button
                class="btn btn--secondary"
                type="button"
                aria-haspopup="dialog"
                aria-controls="tools"
                data-window-open
              >
                Agent Tools
              </button>
            </div>
          </section>

          <section class="section" id="regent" aria-labelledby="regent-title">
            <div class="shead">
              <p class="eyebrow">REGENT staking · Base</p>
              <h2 class="shead__title" id="regent-title">$REGENT</h2>
              <p class="shead__lede">
                Stake REGENT to get a slice of all revenue from any Regents Labs product.
              </p>
            </div>
            <div class="split">
              <div>
                <p class="label muted">Payouts</p>
                <ol class="lines">
                  <li>
                    <span class="lines__index">01</span>
                    <p>
                      Each USDC payment is split as it arrives. You earn the payment × your staked REGENT ÷ 100 billion.
                    </p>
                  </li>
                  <li>
                    <span class="lines__index">02</span>
                    <p>The business keeps the share of REGENT that isn't staked.</p>
                  </li>
                  <li>
                    <span class="lines__index">03</span>
                    <p>
                      Revenue comes from every Regents Labs product: Keyfleet, Autolaunch, Patchbay and Techtree. The 80 USDC from each Animata redemption goes to the staking contract too.
                    </p>
                  </li>
                  <li>
                    <span class="lines__index">04</span>
                    <p>Claim USDC at any time. There is no lock-up.</p>
                  </li>
                </ol>
              </div>
              <div class="stack">
                <div class="tallies">
                  <div class="tally">
                    <span class="label muted">Total</span>
                    <span class="tally__figure">100 billion REGENT</span>
                  </div>
                </div>
                <div class="actions">
                  <Marketing.cta_button label="Stake REGENT" href="/stake" />
                  <a class="btn btn--secondary" href="/redeem">
                    Redeem Animata
                    <svg class="btn__arrow" viewBox="0 0 16 16" aria-hidden="true">
                      <path class="btn__shaft" d="M3 8h10" />
                      <path class="btn__head" d="m7 4 4 4-4 4" />
                    </svg>
                  </a>
                </div>
                <div class="shead__links">
                  <a class="go" href={@buy_url} target="_blank" rel="noopener noreferrer">
                    Buy $REGENT<span class="visually-hidden">, opens in a new tab</span>
                    <svg class="icon" aria-hidden="true"><use href="#icon-arrow" /></svg>
                  </a>
                  <a class="go" href={@chart_url} target="_blank" rel="noopener noreferrer">
                    View Chart<span class="visually-hidden">, opens in a new tab</span>
                    <svg class="icon" aria-hidden="true"><use href="#icon-arrow" /></svg>
                  </a>
                </div>
              </div>
            </div>
          </section>

          <section class="section" id="reading" aria-labelledby="reading-title">
            <div class="shead">
              <h2 class="shead__title" id="reading-title">Reading</h2>
            </div>
            <ul class="plates">
              <li class="card-slot">
                <a class="plate" href="/paper-pro-daily">
                  <span class="plate__index">01</span>
                  <span class="plate__name">Daily Research</span>
                  <svg class="icon" aria-hidden="true"><use href="#icon-next" /></svg>
                </a>
              </li>
              <li class="card-slot">
                <a class="plate" href="/literature">
                  <span class="plate__index">02</span>
                  <span class="plate__name">AI &amp; SCIFI</span>
                  <svg class="icon" aria-hidden="true"><use href="#icon-next" /></svg>
                </a>
              </li>
              <li class="card-slot">
                <a class="plate" href="/about">
                  <span class="plate__index">03</span>
                  <span class="plate__name">About</span>
                  <svg class="icon" aria-hidden="true"><use href="#icon-next" /></svg>
                </a>
              </li>
            </ul>
          </section>

          <section class="band" aria-labelledby="band-title">
            <h2 class="band__line" id="band-title">Regents Labs</h2>
            <p class="band__sentence">
              We build platforms for persistent agents. All revenue is converted to USDC and split with $REGENT stakers.
            </p>
            <div class="actions">
              <Marketing.cta_button label="Enter App" href="/app" />
              <button
                class="btn btn--secondary"
                type="button"
                aria-haspopup="dialog"
                aria-controls="tools"
                data-window-open
              >
                Agent Tools
              </button>
            </div>
          </section>

          <Marketing.footer current="regents" huge="Regents" />
        </div>
      </main>

      <Marketing.agent_tools_dialog />
      <div class="visually-hidden" id="announce" role="status"></div>
    </div>
    """
  end

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
    >
      <span class="rg-button__label">
        {@proof.link.label}<span class="visually-hidden">, opens in a new tab</span>
      </span>
    </a>
    """
  end

  defp status_label(:live), do: "Available now"
  defp status_label(:experimental), do: "Experimental"
  defp status_label(:planned), do: "Planned"

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
          "Launch a memecoin paired with a tokenized stock on Base or Robinhood Chain, sell calls on your stock, or raise early backing for an agent that earns.",
        site: "https://autolaunch.sh",
        github: "https://github.com/regents-ai/autolaunch"
      },
      %{
        name: "techtree",
        line:
          "Custom Skills, evaluations, training environments, and open-weight models, built around your workflows, with results you can measure.",
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
        title: "Onchain stock offerings.",
        description: summaries["autolaunch"],
        action: "launch",
        supporting: nil,
        story: nil,
        proofs: [
          %{
            title: "Fair auctions.",
            copy:
              "Fair auctions on Uniswap's contracts, on Base and Robinhood Chain, in two kinds.",
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
        title: "Better agents for your business.",
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
            link: %{label: "Run locally", href: "/techtree/docs/run-locally"}
          },
          %{
            title: "NVIDIA Skill2Env.",
            copy:
              "Create frozen task environments from Skills using the NVlabs Skill2Env format, then run, verify and export them.",
            status: :experimental,
            link: %{label: "See Environments", href: "/techtree/services/environments"}
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
