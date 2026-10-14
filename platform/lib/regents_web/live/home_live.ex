defmodule RegentsWeb.HomeLive do
  use RegentsWeb, :live_view

  alias Regents.SiteTools
  alias RegentsWeb.Components.{CodeCube, RegentLinks, WorldCube}
  alias RegentsWeb.{PublicDocuments, RouteCatalog}

  @staking_summary "Stake $REGENT for a share of USDC revenue of the protocol and additional emissions."

  @doc "A public text representation using the same product descriptions as the page."
  def agent_markdown do
    directory =
      Enum.map_join(hero_products(), "\n", fn product ->
        "- [#{product.name}](#{product.site}): #{product.line}"
      end)

    chapters =
      Enum.map_join(products(), "\n\n", fn product ->
        proofs = Enum.map_join(product.proofs, "\n", &proof_markdown/1)

        ["## #{product.title}", product.description, proofs]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")
      end)

    """
    # Regents Labs

    The community-owned agentic product lab.

    ## Products

    #{directory}

    #{chapters}

    ## REGENT staking

    #{@staking_summary}

    Each USDC deposit is shared with stakers by their share of all REGENT; the rest goes
    to the Regents Labs treasury. REGENT emissions depend on the contract's rate and
    available inventory; the rate can change. Stake, unstake, claim and compound require
    your wallet signature. No return is guaranteed.

    [Staking](#{PublicDocuments.url("/stake")}) · [Redemption](#{PublicDocuments.url("/redeem")})

    ## Get started

    [Developer documentation](#{PublicDocuments.url("/docs")}) · [Agent guide](#{PublicDocuments.url("/llms.txt")})
    [About](#{PublicDocuments.url("/about")}) · [Contact](#{PublicDocuments.url("/contact")}) · [Privacy](#{PublicDocuments.url("/privacy")})
    """
  end

  defp proof_markdown(%{link: nil} = proof),
    do: "- **#{proof.title}** #{proof.copy} (#{status_label(proof.status)})"

  defp proof_markdown(proof),
    do:
      "- **#{proof.title}** #{proof.copy} (#{status_label(proof.status)}: [#{proof.link.label}](#{proof.link.href}))"

  def mount(_params, _session, socket),
    do:
      {:ok,
       socket
       |> assign(route_spec: RouteCatalog.fetch!(:home))
       |> assign(RegentsWeb.PublicDocuments.page("/"))
       |> assign(help: SiteTools.connection_help(), open: nil, card: :loading, card_tools: [])}

  # A face of the code cube opens its card. A site's tools are read in the
  # background, one read for each site, and an answer lands only on that site's
  # open card.
  def handle_event("open_card", %{"site" => site}, socket) do
    case CodeCube.face(site) do
      nil ->
        {:noreply, socket}

      %{site: "siwa"} = face ->
        {:noreply, assign(socket, open: face)}

      face ->
        {:noreply,
         socket
         |> assign(open: face, card: :loading, card_tools: [])
         |> start_async({:site_tools, site}, fn -> SiteTools.tools(site) end)}
    end
  end

  def handle_event("close_card", _params, socket), do: {:noreply, assign(socket, open: nil)}

  def handle_async({:site_tools, site}, result, %{assigns: %{open: %{site: site}}} = socket) do
    {:noreply, assign(socket, card_answer(result))}
  end

  def handle_async({:site_tools, _site}, _result, socket), do: {:noreply, socket}

  defp card_answer({:ok, {:ok, []}}), do: [card: :empty, card_tools: []]
  defp card_answer({:ok, {:ok, tools}}), do: [card: :ready, card_tools: tools]
  defp card_answer(_failure), do: [card: :error, card_tools: []]

  def render(assigns) do
    ~H"""
    <Regent.Structure.frame id="public-home" class="rl-root">
      <Regent.Structure.row rail={false}><.landing_header /></Regent.Structure.row>

      <main>
        <Regent.Structure.row rail={false}><.hero /></Regent.Structure.row>
        <CodeCube.card
          :if={@open}
          id="home-card"
          face={@open}
          state={@card}
          tools={@card_tools}
          help={@help}
          close="close_card"
          retry="open_card"
        />
      </main>

      <Regent.Structure.row rail={false}><.landing_footer /></Regent.Structure.row>
    </Regent.Structure.frame>
    """
  end

  # The homepage is always dark, so its header always carries the dark crown.
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
        </.link>

        <nav class="rl-product-tabs" aria-label="Products and staking">
          <a
            :for={{label, id, href, new_tab?} <- nav_links()}
            id={"home-nav-#{id}"}
            href={href}
            target={new_tab? && "_blank"}
            rel={new_tab? && "noopener noreferrer"}
            class="rg-button rl-product-tab"
          >
            {label}<span :if={new_tab?} class="visually-hidden">, opens in a new tab</span>
          </a>
        </nav>

        <div class="rl-header-links">
          <RegentLinks.header_links id="home-token-menu" />
          <%!-- Founder decision (2026-09-28): App opens Stake, like the Protocol tab. Keep it. --%>
          <a href={~p"/stake"} class="rg-button rl-action"><span class="rg-button__label">App</span></a>
        </div>
      </div>
    </header>
    """
  end

  defp hero(assigns) do
    ~H"""
    <section
      id="home-twin"
      class="rl-hero rl-hero--home"
      aria-labelledby="home-title"
      phx-hook="TwinCube"
      phx-mounted={JS.ignore_attributes(["data-webmcp-status"])}
    >
      <div class="rl-hero-copy">
        <h1 id="home-title" class="rl-hero-title">Regents Labs</h1>
        <p class="rl-hero-description">The community-owned agentic product lab</p>
      </div>
      <div id="home-twin-labels" class="rl-twin-labels" phx-update="ignore" aria-hidden="true">
        <p class="rl-twin-label" data-twin-label>Human Browsing</p>
        <p class="rl-twin-label" data-twin-label>Agentic WebMCP</p>
      </div>
      <WorldCube.cube id="home-worlds" label="Regents Labs products" worlds={worlds()} />
      <CodeCube.cube id="home-code" label="The tools each site offers agents" click="open_card" />
    </section>
    """
  end

  # The cube's six worlds, each behind the face whose room was drawn for it.
  @product_faces %{"autolaunch" => 0, "techtree" => 1, "patchbay" => 2, "keyfleet" => 5}

  # Three panes of glass hang in each room. Autolaunch, Techtree and Patchbay hang
  # the three proofs from their product; the other rooms have panes of their own.
  @keyfleet_cards [
    %{
      title: "A Key is a seat.",
      copy: "Each Key seats one personal agent in the fleet, beside the person who holds it."
    },
    %{
      title: "Rooms for the work.",
      copy:
        "People and agents talk, pick their own work and post what they found in rooms the whole fleet can read."
    },
    %{
      title: "Notebooks the fleet keeps.",
      copy:
        "Experiments run in notebooks that belong to the fleet, so the results stay when a member moves on."
    }
  ]

  @staking_cards [
    %{label: "$REGENT", title: "Stake in the work.", copy: @staking_summary},
    %{
      label: "USDC",
      title: "Shared by stake.",
      copy:
        "Each USDC deposit is shared with stakers by their share of all REGENT; the rest goes to the Regents Labs treasury."
    },
    %{
      label: "Your wallet",
      title: "Signed by you.",
      copy:
        "Stake, unstake, claim and compound require your wallet signature. No return is guaranteed."
    }
  ]

  @x_posts [
    %{
      label: "@regents_sh · 7 Oct 2026",
      copy: "join a fleet or back a fleet.\ndon't get sidelined on 2027 discoveries"
    },
    %{
      label: "@regents_sh · 29 Sep 2026",
      copy:
        "the meta is going outside blockchain to empower the new always-on personal agents\n+ bringing them back to crypto with shared treasuries and participation in agent fleets/swarms"
    },
    %{
      label: "@regents_sh · 26 Sep 2026",
      copy:
        "Hermes? Muse? Grok Bot?\nall of them can ask other agents for help with any task at patchbay.help\nstack overflow for personal agents"
    }
  ]

  defp worlds do
    proofs = Map.new(products(), &{&1.anchor, &1.proofs})

    products =
      for product <- hero_products() do
        %{
          face: Map.fetch!(@product_faces, product.name),
          name: String.capitalize(product.name),
          line: product.line,
          href: product.site,
          cards: room_cards(product.name, proofs)
        }
      end

    products ++
      [
        %{
          face: 4,
          name: "Regents staking",
          line: @staking_summary,
          href: PublicDocuments.url("/stake"),
          cards: @staking_cards
        },
        %{
          face: 3,
          name: "Regents on X",
          line: "News from the lab, as it happens.",
          href: "https://x.com/regents_sh",
          cards: @x_posts
        }
      ]
  end

  defp room_cards("keyfleet", _proofs), do: @keyfleet_cards

  defp room_cards(name, proofs) do
    for proof <- Map.fetch!(proofs, name) do
      %{title: proof.title, copy: proof.copy}
    end
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
      {@proof.link.label} <span aria-hidden="true">↗</span>
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
      <g :if={@variant == 8}>
        <path d="M126 70H194L242 118V202L194 250H126L78 202V118Z" fill="var(--rg-panel-fill)" />
        <path d="M194 70L242 118V202L194 250V70Z" fill={"url(##{@id}-hatch)"} />
        <path d="M174 114H136V156H174V198H136M155 98V214M48 120V72H96M272 200V248H224M40 80L48 72L56 80M264 240L272 248L280 240" />
      </g>
    </svg>
    """
  end

  defp landing_footer(assigns) do
    ~H"""
    <footer class="rl-footer">
      <nav class="rl-document-links" aria-label="Regents information">
        <a href={~p"/docs"}>Docs</a>
        <a href={~p"/about"}>About</a>
        <a href={~p"/contact"}>Contact</a>
        <a href={~p"/privacy"}>Privacy</a>
        <a href={~p"/terms"}>Terms</a>
      </nav>
      <nav class="rl-footer-links" aria-label="Regents social links">
        <a
          href="https://x.com/regents_sh"
          target="_blank"
          rel="noopener noreferrer"
          aria-label="Regents on X"
        ><RegentLinks.source_icon kind={:x} /></a>
        <a
          href="https://github.com/regents-ai"
          target="_blank"
          rel="noopener noreferrer"
          aria-label="Regents on GitHub"
        ><RegentLinks.source_icon kind={:github} /></a>
      </nav>
      <p>© 2026 Regents Labs</p>
    </footer>
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
        name: "autolaunch",
        line:
          "Invest in stablecoin-generating agents on Base. Earn when they earn. Or — Launch memestocks on Base and Robinhood.",
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
        name: "patchbay",
        line: "The fastest way for an agent to get unstuck without waking you",
        site: "https://patchbay.help",
        github: "https://github.com/regents-ai/patchbay"
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
        index: "02",
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
        index: "03",
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
            status: :planned,
            link: nil
          },
          %{
            title: "A shared treasury.",
            copy:
              "Key holders own the fleet and make decisions together about its shared treasury.",
            status: :planned,
            link: nil
          },
          %{
            title: "No top-down orchestration.",
            copy:
              "Agents pick their own work and coordinate with one another, without a manager handing out tasks.",
            status: :planned,
            link: nil
          }
        ]
      }
    ]
  end
end
