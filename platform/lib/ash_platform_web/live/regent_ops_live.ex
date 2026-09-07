defmodule AshPlatformWeb.RegentOpsLive do
  @moduledoc false
  use Phoenix.Component

  alias AshPlatformWeb.TokenDisplay

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :notice, :map, default: nil
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :account, :map, default: nil

  # The Overview is a product map first. Everything above the account disclosure
  # is public copy that renders whether or not the staking reading has arrived,
  # and whether or not anyone is signed in.
  def page(assigns) do
    ~H"""
    <section id="regent-ops-overview" class="regent-ops-page">
      <header class="regent-ops-heading">
        <p class="regent-ops-kicker">Regents Labs</p>
        <h1 id="regent-ops-heading" tabindex="-1">
          Four products for agents and the people who run them.
        </h1>
        <p class="regent-ops-lede">
          Regents Labs builds tools for agents that need an identity, a wallet, a way to
          launch, a way to prove they are getting better and a place to fix the tools they
          use. Start with any one of them.
        </p>
      </header>

      <ul class="regent-ops-products" aria-label="Products">
        <li class="regent-ops-product regent-ops-product-regents">
          <p class="regent-ops-kicker">regents.sh</p>
          <h2>Regents</h2>
          <p>
            Agent identity and operations, with the REGENT token, staking and Animata
            redemption on Base.
          </p>
          <nav class="regent-ops-product-links" aria-label="Regents pages">
            <.link patch="/stake">Stake</.link>
            <.link patch="/redeem">Redeem</.link>
          </nav>
        </li>
        <li class="regent-ops-product regent-ops-product-autolaunch">
          <p class="regent-ops-kicker">autolaunch.sh</p>
          <h2>Autolaunch</h2>
          <p>Agent token launches and funding, from auction to a live token on Base.</p>
          <nav class="regent-ops-product-links" aria-label="Autolaunch site">
            <.external href="https://autolaunch.sh">Open Autolaunch</.external>
          </nav>
        </li>
        <li class="regent-ops-product regent-ops-product-techtree">
          <p class="regent-ops-kicker">techtree.sh</p>
          <h2>Techtree</h2>
          <p>Measure and verify improvements to agent skills with controlled evaluations.</p>
          <nav class="regent-ops-product-links" aria-label="Techtree site">
            <.external href="https://techtree.sh">Open Techtree</.external>
          </nav>
        </li>
        <li class="regent-ops-product regent-ops-product-patchbay">
          <p class="regent-ops-kicker">patchbay.help</p>
          <h2>Patchbay</h2>
          <p>
            Share the ways agent tools fail and how they were fixed, and collaborate on
            browser tools through WebMCP.
          </p>
          <nav class="regent-ops-product-links" aria-label="Patchbay site">
            <.external href="https://patchbay.help">Open Patchbay</.external>
          </nav>
        </li>
      </ul>

      <details class="regent-ops-details regent-ops-fit">
        <summary>
          <span>How the products fit together</span>
          <.chevron class="regent-ops-chevron" />
        </summary>
        <div class="regent-ops-details-body">
          <p>
            Regents gives an agent an identity and a wallet, and is where REGENT is staked and
            Animata redemptions are claimed. Autolaunch launches and funds agent tokens.
            Techtree measures and verifies improvements to agent skills. Patchbay collects the
            ways agent tools fail and how they were fixed.
          </p>
          <p>
            REGENT is the token behind Regents: it is what is staked here and what an eligible
            Animata redemption pays out.
          </p>
          <p>
            Staking shares USDC as it is actually deposited into the staking contract, so
            rewards depend on deposits received. Current balances and rewards are readings on
            the <.link patch="/stake">Stake</.link> page.
          </p>
        </div>
      </details>

      <details
        id="regent-ops-account"
        class="regent-ops-details regent-ops-account"
        open={@account_control.kind == :signed_in}
      >
        <summary>
          <span>
            <span class="regent-ops-kicker">Your account</span>
            <span class="regent-ops-summary-label">
              {if @account_control.kind == :signed_in,
                do: @account_control.label,
                else: "Network and sign-in"}
            </span>
          </span>
          <.chevron class="regent-ops-chevron" />
        </summary>

        <div class="regent-ops-details-body">
          <div :if={@status == :loading} class="regent-ops-status" aria-busy="true">
            Loading network details…
          </div>

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
                <p class="regent-ops-wallet">{short_wallet(@account && @account.wallet_address)}</p>
              </div>

              <dl class="regent-ops-balances">
                <.metric
                  label="Available REGENT"
                  amount={@staking.wallet_token_balance}
                  unit="REGENT"
                />
                <.metric label="Available USDC" amount={@staking.wallet_usdc_balance} unit="USDC" />
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
            <.link patch="/formation">Run your Regent</.link>
            <.link :if={@account_control.profile_path} patch={@account_control.profile_path}>
              View Regent profile
            </.link>
          </nav>
        </div>
      </details>
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

  attr :class, :string, required: true

  # A down chevron; the stylesheet turns it over while its disclosure is open.
  defp chevron(assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
      <path
        d="M3 6l5 5 5-5"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
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

  defp short_wallet("0x" <> address) when byte_size(address) == 40,
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short_wallet(_wallet), do: "No verified wallet"
end
