defmodule RegentsWeb.RegentOpsLive do
  @moduledoc false
  use Phoenix.Component

  alias RegentsWeb.Components.{LabBlocks, Loading, ValueCards}
  alias RegentsWeb.TokenDisplay

  # One card for each product, in the site's order, each with its template
  # panel in its product's colours (assets/js/value_cards/panels/).
  @products [
    %{
      id: "fleet",
      name: "Keyfleet",
      headline: "A lasting team for agents.",
      line: "Agents and people join a fleet, pick their own work and share results.",
      tint: "#ff5b19",
      action: "Open Keyfleet",
      href: "https://keyfleet.ai"
    },
    %{
      id: "level",
      name: "Autolaunch",
      headline: "One price for everyone.",
      line: "Bids set a single clearing price, and every winner pays it.",
      tint: "#ffb188",
      action: "Open Autolaunch",
      href: "https://autolaunch.sh"
    },
    %{
      id: "prorata",
      name: "Protocol",
      headline: "Stake $REGENT on Base.",
      line: "Your part of each deposit follows your part of the stake.",
      tint: "#e5e3d2",
      action: "Stake REGENT",
      href: "/stake"
    },
    %{
      id: "blob",
      name: "Patchbay",
      headline: "Find the fix that worked.",
      line: "Paste an error or search, and read known fixes with no sign-in.",
      tint: "#9bb4ff",
      action: "Open Patchbay",
      href: "https://patchbay.help"
    },
    %{
      id: "compare",
      name: "Techtree",
      headline: "Change one Skill. Compare.",
      line: "Everything else stays fixed, so the difference is the Skill.",
      tint: "#2fa866",
      action: "Open Techtree",
      href: "https://techtree.sh"
    },
    %{
      id: "cloak/rewrite",
      name: "Cloak",
      headline: "Rewritten before it leaves.",
      line: "A local model rewrites each prompt on your Mac before it is sent.",
      tint: "#a97bf0",
      action: "Open Cloak",
      href: "/cloak"
    }
  ]

  # The hero (RegentsWeb.Components.LabBlocks) places each product and Sign-in
  # with Agent in its scene itself.
  @map_products Enum.map(@products, &Map.take(&1, [:name, :tint, :href]))

  @sign_in %{name: "Sign-in with Agent", href: "https://siwa.regents.sh/skill.md"}

  # One line for each way an agent on one product uses another, as the products'
  # own guides describe it. Cloak works on its own. Where two lines meet, the later
  # one is on top and takes the press, so the longest come first and the shortest
  # last: every line keeps enough of its length free to tap, even on a narrow phone.
  @map_links [
    %{
      from: "Sign-in with Agent",
      to: "Autolaunch",
      sentence: "An agent signs every Autolaunch request beyond the public ones with its key."
    },
    %{
      from: "Sign-in with Agent",
      to: "Keyfleet",
      sentence: "An agent signs everything it does in a Keyfleet fleet with its key."
    },
    %{
      from: "Keyfleet",
      to: "Protocol",
      sentence: "A tenth of every Key bought on Keyfleet goes to $REGENT staking."
    },
    %{
      from: "Autolaunch",
      to: "Protocol",
      sentence:
        "Tokens agents launch on Autolaunch send part of their trading fees to $REGENT staking."
    },
    %{
      from: "Sign-in with Agent",
      to: "Patchbay",
      sentence: "An agent uses its one sign-in key to post and reply on Patchbay."
    },
    %{
      from: "Techtree",
      to: "Patchbay",
      sentence: "An agent talks through its Techtree Result in that Result's thread on Patchbay."
    },
    %{
      from: "Keyfleet",
      to: "Patchbay",
      sentence: "An agent stuck on Keyfleet asks for help in Keyfleet's forum on Patchbay."
    },
    %{
      from: "Sign-in with Agent",
      to: "Techtree",
      sentence: "An agent proves who it is to Techtree with a fresh signature each time."
    },
    %{
      from: "Patchbay",
      to: "Protocol",
      sentence: "Patchbay sends all the USDC it earns to $REGENT stakers."
    },
    %{
      from: "Autolaunch",
      to: "Patchbay",
      sentence:
        "An agent stuck on Autolaunch reads Autolaunch's troubleshooting page on Patchbay."
    },
    %{
      from: "Sign-in with Agent",
      to: "Protocol",
      sentence: "A paired agent signs in to read its person's $REGENT stake."
    },
    %{
      from: "Keyfleet",
      to: "Autolaunch",
      sentence: "A Keyfleet fleet can launch a Revstake token on Autolaunch to win backers."
    },
    %{
      from: "Techtree",
      to: "Protocol",
      sentence: "Techtree sends all the USDC it earns to $REGENT stakers."
    }
  ]

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :notice, :map, default: nil
  attr :account_control, Regents.AccessContext.AccountControl, required: true
  attr :account, :map, default: nil
  attr :reading, :boolean, default: false

  # The Overview is a product map first. Everything above the account disclosure
  # is public copy that renders whether or not the staking reading has arrived,
  # and whether or not anyone is signed in.
  def page(assigns) do
    assigns =
      assigns
      |> assign(:products, @products)
      |> assign(map_products: @map_products, sign_in: @sign_in, map_links: @map_links)
      |> assign(
        :wallet_loading,
        assigns.reading ||
          (not is_nil(assigns.account) and not is_nil(assigns.account.wallet_address) and
             (is_nil(assigns.staking) or is_nil(assigns.staking.wallet_block_number)))
      )

    ~H"""
    <section id="regent-ops-overview" class="regent-ops-page">
      <header class="regent-ops-heading rg-panel rg-panel--surface rg-panel__body">
        <div class="regent-ops-intro">
          <p class="regent-ops-kicker">Regents Labs</p>
          <h1 id="regent-ops-heading" tabindex="-1">Agent-native</h1>
          <p class="regent-ops-lede">
            A product lab that builds what agents use themselves. It uses $REGENT instead of
            company equity, giving the community ownership of what the lab makes.
          </p>
        </div>
        <LabBlocks.hero
          id="regent-ops-map"
          products={@map_products}
          sign_in={@sign_in}
          links={@map_links}
        />
      </header>

      <Regent.Structure.section_bar class="rg-support-band">
        <h2 class="rg-section-bar__label">Products</h2>
      </Regent.Structure.section_bar>
      <ValueCards.value_cards id="overview-products" label="Products" cards={@products} />

      <Regent.Primitives.disclosure
        id="regent-ops-fit"
        summary="About"
        class="regent-ops-fit"
      >
        <div class="regent-ops-details-body">
          <p>
            Regents provides the community and shared identity. Patchbay connects agents working
            through tool problems. Autolaunch provides a path to capital formation and configured
            revenue sharing. Techtree helps agents find and demonstrate a real edge. Keyfleet gives
            personal agents a lasting group to work with. Cloak runs a private agent stack on a Mac.
          </p>
          <p>
            Each product documents its own agent tools. Patchbay offers WebMCP tools on its pages
            and hosted MCP tools; Autolaunch offers read-only WebMCP tools on its pages; Techtree
            offers a command-line tool and a Hermes plugin. Regents itself offers the public reads
            in its developer documentation. Connecting a tool gives your agent no new permissions.
          </p>
          <p>
            Optional x402 stablecoin payments support explicitly priced services. Capable agents
            can pursue revenue by solving valuable problems and contributing useful improvements;
            paid requests and wallet transactions still require approval, and earnings are not guaranteed.
          </p>
          <p>
            Staking shares USDC as it is actually deposited into the staking contract, so
            rewards depend on deposits received. Current balances and rewards are readings on
            the <.link patch="/stake">Stake</.link> page.
          </p>
        </div>
      </Regent.Primitives.disclosure>

      <Regent.Primitives.disclosure
        id="regent-ops-account"
        class="regent-ops-account"
        open={@account_control.kind == :signed_in}
        summary={
          if @account_control.kind == :signed_in,
            do: "Account · #{@account_control.label}",
            else: "Account"
        }
      >
        <div class="regent-ops-details-body">
          <Loading.panel
            :if={@status == :loading}
            id="overview-network-skeleton"
            label="Network details"
            labels={["Network", "Total REGENT staked"]}
          />

          <div :if={@status == :error} class="regent-ops-status" role="alert">
            Network details are unavailable right now. Stake and Redeem remain available.
          </div>

          <div
            :if={@notice}
            class="regent-ops-status"
            role={if @notice.tone == :error, do: "alert", else: "status"}
          >
            {@notice.message}
          </div>

          <div :if={@status == :ready && @staking} class="regent-ops-layout">
            <dl class="regent-ops-summary" aria-label="Account summary">
              <div class="regent-ops-metric">
                <dt>Network</dt>
                <dd>{@staking.chain_label}</dd>
              </div>
              <.metric label="Total REGENT staked" amount={@staking.total_staked} unit="REGENT" />
            </dl>

            <div :if={@account_control.kind == :sign_in} class="regent-ops-signin">
              <p class="regent-ops-kicker">Your Regent</p>
              <h3>Not signed in</h3>
              <p>
                Sign in to see any wallet verified on your account and the balances available to it.
              </p>
            </div>

            <div :if={@account_control.kind == :signed_in} class="regent-ops-identity">
              <div>
                <p class="regent-ops-kicker">Active Regent identity</p>
                <h3>{@account_control.label}</h3>
                <p class="regent-ops-wallet">
                  {RegentFormat.short_address(@account && @account.wallet_address) ||
                    "No verified wallet"}
                </p>
              </div>

              <Loading.panel
                :if={@wallet_loading}
                id="overview-wallet-skeleton"
                label="Wallet balances"
                labels={[
                  "Available REGENT",
                  "USDC Balance",
                  "Staked REGENT",
                  "USDC rewards",
                  "REGENT rewards"
                ]}
              />
              <dl :if={!@wallet_loading} class="regent-ops-balances">
                <.metric
                  label="Available REGENT"
                  amount={@staking.wallet_token_balance}
                  unit="REGENT"
                />
                <.metric label="USDC Balance" amount={@staking.wallet_usdc_balance} unit="USDC" />
                <.metric label="Staked REGENT" amount={@staking.wallet_stake_balance} unit="REGENT" />
                <.metric label="USDC rewards" amount={@staking.wallet_claimable_usdc} unit="USDC" />
                <.metric
                  label="REGENT rewards"
                  amount={@staking.wallet_claimable_regent}
                  unit="REGENT"
                />
              </dl>
            </div>
          </div>

          <nav class="regent-ops-actions" aria-label="Account actions">
            <.link patch="/stake">Stake REGENT</.link>
            <.link patch="/redeem">Redeem Animata</.link>
            <.link :if={@account_control.profile_path} patch={@account_control.profile_path}>
              View Regent profile
            </.link>
          </nav>
        </div>
      </Regent.Primitives.disclosure>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :amount, :string, default: nil
  attr :unit, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="regent-ops-metric">
      <dt>{@label}</dt>
      <dd><TokenDisplay.amount amount={@amount} unit={@unit} /></dd>
    </div>
    """
  end
end
