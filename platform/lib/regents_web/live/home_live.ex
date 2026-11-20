defmodule RegentsWeb.HomeLive do
  use RegentsWeb, :live_view

  alias RegentsWeb.Components.{AgentTools, RegentLinks, Shell}
  alias RegentsWeb.Live.Session
  alias RegentsWeb.{PublicDocuments, RegentOpsLive, RouteCatalog}
  alias RegentsWeb.Stake.TokenLinks

  # The lab's one plain line under its name, and the quieter line under that, on
  # the page and in the agent copy.
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

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(route_spec: RouteCatalog.fetch!(:home))
     |> assign(account_control: Session.account_control(session))
     |> assign(PublicDocuments.page("/"))}
  end

  # The page in its window frame: the name as large as the window allows, the two
  # lines and the two ways in beside it, the opening picture, the agent prompt, a row
  # for each product on the home colour's slab, $REGENT and the foot. Every colour
  # is the home colour's (`--rg-home-*`); each picture is a field of dots painted in
  # it (`pages/home_pictures.css`).
  def render(assigns) do
    assigns =
      assign(assigns,
        mission: @mission,
        mission_note: @mission_note,
        agent_prompt: agent_prompt(),
        products: RegentOpsLive.products()
      )

    ~H"""
    <div id="public-home" class="home">
      <a class="shell-skip" href="#home-content">Skip to content</a>
      <Shell.site_bar product="regents" account_control={@account_control} />
      <div class="home-frame" aria-hidden="true"></div>

      <main id="home-content" class="home__main">
        <div class="home__hero">
          <h1 id="home-title" class="home__name" tabindex="-1">Regents Labs</h1>
          <div class="home__lead">
            <div class="home__words">
              <p>{@mission}</p>
              <p>{@mission_note}</p>
            </div>
            <div class="home__actions">
              <a id="home-enter" href={~p"/app"} class="rg-button rg-button--no-arrow home__enter">
                <span class="rg-button__label">Enter App</span>
              </a>
              <AgentTools.button
                id="home-agent-tools-button"
                dialog="home-agent-tools"
                class="rg-button rg-button--secondary rg-button--no-arrow home__tools"
              >
                <span class="rg-button__label">Agent Tools</span>
              </AgentTools.button>
            </div>
          </div>
        </div>

        <div class="home__picture pic pic--hero" aria-hidden="true"></div>

        <%!-- The words a person pastes to their agent; the whole prompt is copied, or
             shown in its own window. --%>
        <section class="home__prompt" aria-labelledby="home-prompt-title">
          <h2 id="home-prompt-title" class="home__label">Agent prompt</h2>
          <p id="home-prompt-text" class="home__prompt-text">{@agent_prompt}</p>
          <div class="home__prompt-tools">
            <Regent.Primitives.copy_icon id="home-prompt-copy" target="home-prompt-text" label="Copy" />
            <button
              id="home-prompt-view"
              type="button"
              class="home__prompt-view"
              aria-label="View"
              title="View"
              aria-haspopup="dialog"
              aria-controls="home-prompt-dialog"
              phx-click={JS.dispatch("regents:open", to: "#home-prompt-dialog")}
            >
              <Regent.Icons.icon name="maximize-2" />
            </button>
          </div>
        </section>

        <.slab products={@products} />

        <section class="home__token" aria-labelledby="home-token-title">
          <h2 id="home-token-title" class="home__label">$REGENT</h2>
          <Regent.Primitives.address id="home-token-address" address={TokenLinks.address()} />
          <a class="home__link" href={TokenLinks.buy()} target="_blank" rel="noopener noreferrer">
            Buy on Uniswap<span class="visually-hidden">, opens in a new tab</span>
          </a>
          <a class="home__link" href={TokenLinks.chart()} target="_blank" rel="noopener noreferrer">
            View Chart<span class="visually-hidden">, opens in a new tab</span>
          </a>
        </section>

        <footer class="home__footer">
          <p>© 2026 Regents Labs</p>
          <div class="home__social"><RegentLinks.social_links /></div>
        </footer>
      </main>

      <AgentTools.dialog id="home-agent-tools" />
      <.prompt_dialog agent_prompt={@agent_prompt} />
    </div>
    """
  end

  # The whole agent prompt in a window of its own, in the Agent Tools window's
  # colours, closed with its X, Escape or a press beside it.
  defp prompt_dialog(assigns) do
    ~H"""
    <Regent.Structure.dialog
      id="home-prompt-dialog"
      class="agent-tools rl-prompt-dialog"
      aria-labelledby="home-prompt-dialog-title"
      phx-hook="InfoDialog"
      {%{"closedby" => "any"}}
    >
      <header class="agent-tools__head">
        <h2 id="home-prompt-dialog-title">Agent prompt</h2>
        <form method="dialog">
          <button class="agent-tools__close" aria-label="Close">
            <Regent.Icons.icon name="x" />
          </button>
        </form>
        <div class="agent-tools__copies">
          <Regent.Primitives.copy_button id="home-prompt-dialog-copy" target="home-prompt-full">
            Copy
          </Regent.Primitives.copy_button>
        </div>
      </header>
      <div class="agent-tools__body">
        <p id="home-prompt-full" class="rl-prompt-dialog__text">{@agent_prompt}</p>
      </div>
    </Regent.Structure.dialog>
    """
  end

  attr :products, :list, required: true

  # The products in the product menu's order, each with its words and its picture, on
  # the home colour's slab. Each link loads the page the menu lands on, in the same tab.
  defp slab(assigns) do
    ~H"""
    <section class="slab" aria-labelledby="home-products-title">
      <h2 id="home-products-title" class="visually-hidden">Products</h2>
      <article :for={product <- @products} id={"home-#{picture(product)}"} class="slab__row">
        <div class="slab__text">
          <p class="home__label">{product.name}</p>
          <h3 class="slab__headline">{product.headline}</h3>
          <p class="slab__line">{product.line}</p>
          <a class="slab__link" href={product.href}>
            {product.action}
            <Regent.Icons.icon name="arrow-right" />
          </a>
        </div>
        <div class={["slab__pic pic", "pic--#{picture(product)}"]} aria-hidden="true"></div>
      </article>
    </section>
    """
  end

  defp picture(product), do: String.downcase(product.name)

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

  # Each product page reads its own chapter. Every proof says what
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
            link: %{label: "Run locally", href: "https://techtree.sh/docs/run-locally"}
          },
          %{
            title: "NVIDIA Skill2Env.",
            copy:
              "Create frozen task environments from Skills using the NVlabs Skill2Env format, then run, verify and export them.",
            status: :experimental,
            link: %{label: "See Environments", href: "https://techtree.sh/services/environments"}
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
