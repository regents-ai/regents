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

    [Enter App](#{PublicDocuments.url("/stake")})

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
  # While the picture is drawn the panel starts away: pressing a panel in the picture
  # brings it in, and once it has stood for a moment, flying the picture sends it away
  # again. Without scripts, without WebGPU, or with less motion asked for, the
  # server's still picture stays and the panel stays open. The copyright stands at
  # the window's foot throughout, under the panel where the two meet.
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
            <a href={~p"/stake"} class="rg-button rg-button--no-arrow rl-hero-cta">
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
  defp products(assigns) do
    ~H"""
    <nav class="home__foot" aria-labelledby="home-products-title">
      <h2 id="home-products-title" class="rl-overline">Products</h2>
      <div class="rl-product-tabs">
        <a
          :for={{label, id, href, new_tab?} <- nav_links()}
          id={"home-nav-#{id}"}
          href={href}
          target={new_tab? && "_blank"}
          rel={new_tab? && "noopener noreferrer"}
          class="rg-button rl-product-tab"
          phx-hook="HolographicCard"
          data-holo-crown="false"
          data-holo-shine="0.65"
        >
          <Regent.HolographicCard.foil id={"home-nav-#{id}-foil"} class="rl-product-tab__foil" />
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

  attr :id, :string, required: true
  attr :variant, :integer, required: true

  # The product Overview's drawings, kept beside the product list they illustrate.
  def card_diagram(assigns) do
    ~H"""
    <svg
      id={@id}
      class="rl-card-diagram"
      data-diagram={@variant}
      viewBox="0 0 320 320"
      fill="none"
      stroke="currentColor"
      stroke-width="1.2"
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <pattern id={"#{@id}-hatch"} width="7" height="7" patternUnits="userSpaceOnUse">
          <path d="M-2 2L2-2M0 7L7 0M5 9L9 5" stroke-width=".65" />
        </pattern>
      </defs>
      <path d="M8 28V8H28M292 8H312V28M312 292V312H292M28 312H8V292" />
      <g :if={@variant == 0}>
        <path d="M86 50H204L244 90V266H86Z" fill="var(--rg-panel-fill)" />
        <path d="M204 50V90H244M66 72V282H220M108 116H218M108 134H186M108 212H218M108 230H174" />
        <rect x="108" y="158" width="46" height="32" fill={"url(##{@id}-hatch)"} />
        <path d="M176 160H218M176 176H204M176 190H218" />
      </g>
      <g :if={@variant == 1}>
        <path d="M56 70V252M264 70V252M48 90H272M48 136H272M48 182H272M48 228H272" />
        <rect x="82" y="77" width="46" height="26" fill="var(--rg-panel-fill)" />
        <rect x="178" y="123" width="46" height="26" fill="var(--rg-panel-fill)" />
        <rect x="122" y="169" width="46" height="26" fill={"url(##{@id}-hatch)"} />
        <rect x="82" y="215" width="46" height="26" fill="var(--rg-panel-fill)" />
        <path d="M145 158V144M138 151H152" />
      </g>
      <g :if={@variant == 2}>
        <path d="M64 196L160 148L256 196V220L160 268L64 220Z" fill="var(--rg-panel-fill)" />
        <path d="M64 196L160 244L256 196M160 244V268" />
        <path d="M64 148L160 100L256 148V172L160 220L64 172Z" fill="var(--rg-panel-fill)" />
        <path d="M64 148L160 196L256 148M160 196V220" />
        <path d="M64 100L160 52L256 100V124L160 172L64 124Z" fill="var(--rg-panel-fill)" />
        <path d="M64 100L160 148L256 100M160 148V172" />
        <path d="M160 148L256 100V124L160 172Z" fill={"url(##{@id}-hatch)"} />
      </g>
      <g :if={@variant == 3}>
        <rect x="60" y="104" width="156" height="144" fill="var(--rg-panel-fill)" />
        <rect x="82" y="82" width="156" height="144" fill="var(--rg-panel-fill)" />
        <rect x="104" y="60" width="156" height="144" fill="var(--rg-panel-fill)" />
        <path d="M104 96H260M120 78H126M136 78H142M152 78H158M122 122H186M122 138H164" />
        <rect x="202" y="122" width="38" height="60" fill={"url(##{@id}-hatch)"} />
        <path d="M122 178H178V156H190" />
      </g>
      <g :if={@variant == 4}>
        <path d="M60 76H132V244H60M188 76H260V244H188M132 160H188" />
        <path d="M60 100H114M60 124H100M60 148H114M60 172H100M60 196H114M60 220H100M206 100H260M220 124H260M206 148H260M220 172H260M206 196H260M220 220H260" />
        <path d="M160 128L192 160L160 192L128 160Z" fill="var(--rg-panel-fill)" />
        <path d="M160 128L192 160L160 192Z" fill={"url(##{@id}-hatch)"} />
      </g>
      <g :if={@variant == 5}>
        <path d="M160 80V132M80 160H132M188 160H240M160 188V240M90 90L132 132M188 188L230 230" />
        <rect x="132" y="132" width="56" height="56" fill={"url(##{@id}-hatch)"} />
        <rect x="144" y="48" width="32" height="32" /><rect x="48" y="144" width="32" height="32" />
        <rect x="240" y="144" width="32" height="32" /><rect x="144" y="240" width="32" height="32" />
        <path d="M70 70H90V90H70ZM230 230H250V250H230Z" />
      </g>
      <g :if={@variant == 6}>
        <path d="M80 80H120V144H150M80 160H150M80 240H120V176H150M196 160H248" />
        <rect x="48" y="64" width="32" height="32" /><rect x="48" y="144" width="32" height="32" />
        <rect x="48" y="224" width="32" height="32" /><rect
          x="150"
          y="112"
          width="46"
          height="96"
          fill={"url(##{@id}-hatch)"}
        />
        <rect x="248" y="132" width="24" height="56" /><path d="M254 146H266M254 160H266M254 174H266" />
      </g>
      <g :if={@variant == 7}>
        <path d="M112 130H264V246H232V270L208 246H112Z" fill="var(--rg-panel-fill)" />
        <path d="M56 56H224V180H110L80 210V180H56Z" fill="var(--rg-panel-fill)" />
        <path d="M80 88H198M80 108H182M80 128H198M80 148H150M140 208H240M140 224H208" />
        <rect x="236" y="146" width="12" height="36" fill={"url(##{@id}-hatch)"} />
      </g>
      <g :if={@variant == 9}>
        <path
          d="M44 92A36 36 0 1 0 116 92A36 36 0 1 0 44 92ZM68 92A12 12 0 1 0 92 92A12 12 0 1 0 68 92Z"
          fill="var(--rg-panel-fill)"
        />
        <path d="M116 92H200V128M152 92V114M176 92V108" />
        <rect x="164" y="128" width="72" height="72" fill={"url(##{@id}-hatch)"} />
        <path d="M200 200V236M200 214H116V236M200 214H284V236" />
        <rect x="94" y="236" width="44" height="44" fill="var(--rg-panel-fill)" />
        <rect x="178" y="236" width="44" height="44" fill="var(--rg-panel-fill)" />
        <rect x="262" y="236" width="44" height="44" fill="var(--rg-panel-fill)" />
        <path d="M106 258H126M190 258H210M274 258H294" />
      </g>
      <g :if={@variant == 8}>
        <path d="M126 70H194L242 118V202L194 250H126L78 202V118Z" fill="var(--rg-panel-fill)" />
        <path d="M194 70L242 118V202L194 250V70Z" fill={"url(##{@id}-hatch)"} />
        <path d="M174 114H136V156H174V198H136M155 98V214M48 120V72H96M272 200V248H224M40 80L48 72L56 80M264 240L272 248L280 240" />
      </g>
    </svg>
    """
  end

  # Each product tab opens that product's site in a new tab; Protocol opens the
  # staking page. Founder decision (2026-09-28): the tab is named Protocol.
  defp nav_links do
    sites =
      for product <- hero_products(),
          do: {String.capitalize(product.name), product.name, product.site, true}

    sites ++ [{"Protocol", "protocol", ~p"/stake", false}]
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
