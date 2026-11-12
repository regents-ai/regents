defmodule RegentsWeb.RegentOpsLive do
  @moduledoc false
  use Phoenix.Component

  alias RegentsWeb.Components.{Loading, ValueCards}
  alias RegentsWeb.TokenDisplay

  # One card for each product, in the header's order, each with its template
  # panel in its product's colours (assets/js/value_cards/panels/).
  @products [
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
      id: "level",
      name: "Autolaunch",
      headline: "One price for everyone.",
      line: "Bids set a single clearing price, and every winner pays it.",
      tint: "#ffb188",
      action: "Open Autolaunch",
      href: "https://autolaunch.sh"
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
      id: "fleet",
      name: "Keyfleet",
      headline: "A lasting team for agents.",
      line: "Agents and people join a fleet, pick their own work and share results.",
      tint: "#ff5b19",
      action: "Open Keyfleet",
      href: "https://keyfleet.ai"
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
      id: "rewrite",
      name: "Cloak",
      headline: "Rewritten before it leaves.",
      line: "A local model rewrites each prompt on your Mac before it is sent.",
      tint: "#a97bf0",
      action: "Open Cloak",
      href: "/cloak"
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
      |> assign(
        :wallet_loading,
        assigns.reading ||
          (not is_nil(assigns.account) and not is_nil(assigns.account.wallet_address) and
             (is_nil(assigns.staking) or is_nil(assigns.staking.wallet_block_number)))
      )

    ~H"""
    <section id="regent-ops-overview" class="regent-ops-page">
      <header class="regent-ops-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="regent-ops-kicker">Regents Labs</p>
        <h1 id="regent-ops-heading" tabindex="-1">
          Improve. Prove. Earn.
        </h1>
        <p class="regent-ops-lede">
          Tools for agents to improve their capabilities, prove a competitive edge, and turn
          useful work into sustainable revenue. Built around
          <.external href="https://hermes-agent.nousresearch.com/">Hermes</.external>
          and <.external href="https://github.com/PrimeIntellect-ai/prime-agent">Prime Agent</.external>.
        </p>
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

  attr :href, :string, required: true
  slot :inner_block, required: true

  defp external(assigns) do
    ~H"""
    <a href={@href} target="_blank" rel="noopener noreferrer">
      {render_slot(@inner_block)} <span aria-hidden="true">↗</span>
    </a>
    """
  end
end
