defmodule AshPlatformWeb.RegentOpsLive do
  @moduledoc false
  use Phoenix.Component

  alias AshPlatformWeb.TokenDisplay

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :account, :map, default: nil

  def page(assigns) do
    ~H"""
    <section id="regent-ops-overview" class="regent-ops-page">
      <header class="regent-ops-heading">
        <p class="regent-ops-kicker">Regents Labs · Base</p>
        <h1>Account</h1>
        <p>See your account, any verified wallet, balances, and rewards on Base.</p>
      </header>

      <div :if={@status == :loading} class="regent-ops-status" aria-busy="true">
        Loading network details…
      </div>

      <div :if={@status == :error} class="regent-ops-status" role="alert">
        Network details are unavailable right now. Stake and Redeem remain available.
      </div>

      <div :if={@status == :ready && @staking} class="regent-ops-layout">
        <dl class="regent-ops-summary" aria-label="Account summary">
          <div class="regent-ops-metric">
            <dt>Network</dt>
            <dd>{@staking.chain_label}</dd>
          </div>
          <.metric label="Total REGENT staked" amount={@staking.total_staked} unit="REGENT" />
        </dl>

        <section :if={@account_control.kind == :sign_in} class="regent-ops-account">
          <p class="regent-ops-kicker">Your Regent</p>
          <h2>Not signed in</h2>
          <p>Sign in to see any wallet verified on your account and the balances available to it.</p>
        </section>

        <section :if={@account_control.kind == :signed_in} class="regent-ops-account">
          <div>
            <p class="regent-ops-kicker">Active Regent identity</p>
            <h2>{@account_control.label}</h2>
            <p class="regent-ops-wallet">{short_wallet(@account && @account.wallet_address)}</p>
          </div>

          <dl class="regent-ops-balances">
            <.metric label="Available REGENT" amount={@staking.wallet_token_balance} unit="REGENT" />
            <.metric label="Available USDC" amount={@staking.wallet_usdc_balance} unit="USDC" />
            <.metric label="Staked REGENT" amount={@staking.wallet_stake_balance} unit="REGENT" />
            <.metric label="USDC rewards" amount={@staking.wallet_claimable_usdc} unit="USDC" />
            <.metric label="REGENT rewards" amount={@staking.wallet_claimable_regent} unit="REGENT" />
          </dl>
        </section>
      </div>

      <nav class="regent-ops-actions" aria-label="Account actions">
        <.link patch="/stake">Stake REGENT</.link>
        <.link patch="/redeem">Redeem Animata</.link>
        <.link patch="/formation">Run your Regent</.link>
        <.link :if={@account_control.profile_path} patch={@account_control.profile_path}>
          View Regent profile
        </.link>
      </nav>
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

  defp short_wallet("0x" <> address) when byte_size(address) == 40,
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short_wallet(_wallet), do: "No verified wallet"
end
