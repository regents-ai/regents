defmodule RegentsWeb.VgpuDemoLive do
  @moduledoc """
  The cube that was the home page until 21 Oct 2026: the products drawn as
  rooms behind the faces of a vgpu cube, on a page of its own.
  """

  use RegentsWeb, :live_view

  alias RegentsWeb.Components.{AgentTools, RegentLinks, WorldCube}
  alias RegentsWeb.{ExampleWorkflows, ProductCatalog, PublicDocuments, RouteCatalog}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(route_spec: RouteCatalog.fetch!(:vgpu_demo))
     |> assign(PublicDocuments.page("/vgpu-demo"))}
  end

  def render(assigns) do
    ~H"""
    <Regent.Structure.frame id="public-home" class="rl-root">
      <Regent.Structure.row rail={false}><.landing_header /></Regent.Structure.row>

      <main>
        <Regent.Structure.row rail={false}>
          <.hero />
        </Regent.Structure.row>
      </main>

      <Regent.Structure.row rail={false}>
        <RegentsWeb.Layouts.product_links theme_toggle={false} />
      </Regent.Structure.row>
    </Regent.Structure.frame>
    """
  end

  # The page is always dark, so its header always carries the dark crown.
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
            phx-hook="HolographicCard"
            data-holo-crown="false"
            data-holo-shine="0.65"
          >
            <Regent.HolographicCard.foil id={"home-nav-#{id}-foil"} class="rl-product-tab__foil" />
            <span class="rg-button__label">
              {label}<span :if={new_tab?} class="visually-hidden">, opens in a new tab</span>
            </span>
          </a>
        </nav>

        <div class="rl-header-links">
          <RegentLinks.header_links id="home-token-menu" />
          <%!-- Founder decision (2026-09-28): App opens staking, like the Protocol tab. Keep it. --%>
          <a href={~p"/"} class="rg-button rl-action"><span class="rg-button__label">App</span></a>
        </div>
      </div>
    </header>
    """
  end

  defp hero(assigns) do
    ~H"""
    <section
      id="home-hero"
      class="rl-hero rl-hero--home"
      aria-labelledby="home-title"
      phx-hook="CubeLabel"
    >
      <div class="rl-hero-copy">
        <h1 id="home-title" class="rl-hero-title">Regents Labs</h1>
        <p class="rl-hero-description">The community-owned agentic product lab</p>
        <div class="rl-hero-actions">
          <AgentTools.button id="home-agent-tools-button" dialog="home-agent-tools" />
        </div>
      </div>
      <AgentTools.dialog id="home-agent-tools" />
      <p id="home-cube-label" class="rl-cube-label" phx-update="ignore" aria-hidden="true">
        Human Browsing
      </p>
      <WorldCube.cube id="home-worlds" label="Regents Labs products" worlds={worlds()} />
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
    %{label: "$REGENT", title: "Stake in the work.", copy: ExampleWorkflows.revenue_split()},
    %{
      label: "USDC",
      title: "Shared by stake.",
      copy: "Credits, Key sales, Patchbay fees and Autolaunch fees send USDC to staking."
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
    proofs = Map.new(ProductCatalog.products(), &{&1.anchor, &1.proofs})

    products =
      for product <- ProductCatalog.hero_products() do
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
          name: "Staking",
          line: "Participate in ecosystem revenue sharing.",
          href: PublicDocuments.url("/"),
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

  # Each product tab opens that product's site in a new tab; Protocol opens
  # staking on the home page. Founder decision (2026-09-28): the tab is named Protocol.
  defp nav_links do
    sites =
      for product <- ProductCatalog.hero_products(),
          do: {String.capitalize(product.name), product.name, product.site, true}

    sites ++ [{"Protocol", "protocol", ~p"/", false}]
  end
end
