defmodule AshPlatformWeb.RegentOpsLive do
  @moduledoc false
  use Phoenix.Component

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :account, :map, default: nil

  def page(assigns) do
    ~H"""
    <section id="regent-ops-overview" class="regent-ops-page">
      <header class="regent-ops-heading">
        <p class="regent-ops-kicker">Regents Labs · Base</p>
        <h1>Regents Labs</h1>
        <p>Manage your Regent identity, REGENT positions, and wallet actions in one place.</p>
      </header>

      <div :if={@status == :loading} class="regent-ops-status" aria-busy="true">
        Loading network details…
      </div>

      <div :if={@status == :error} class="regent-ops-status" role="alert">
        Network details are unavailable right now. Stake and Redeem remain available.
      </div>

      <div :if={@status == :ready && @staking} class="regent-ops-layout">
        <section class="regent-ops-summary" aria-label="Regents Labs summary">
          <.metric label="Network" value={@staking.chain_label} />
          <.metric label="Total REGENT staked" value={token(@staking.total_staked, "REGENT")} />
        </section>

        <section :if={@account_control.kind == :sign_in} class="regent-ops-account">
          <p class="regent-ops-kicker">Your Regent</p>
          <h2>Sign in to see your wallet</h2>
          <p>Your account keeps wallet evidence and Regent actions tied to one human identity.</p>
        </section>

        <section :if={@account_control.kind == :signed_in} class="regent-ops-account">
          <div>
            <p class="regent-ops-kicker">Active Regent identity</p>
            <h2>{@account_control.label}</h2>
            <p class="regent-ops-wallet">{short_wallet(@account && @account.wallet_address)}</p>
          </div>

          <dl class="regent-ops-balances">
            <.metric label="Available REGENT" value={token(@staking.wallet_token_balance, "REGENT")} />
            <.metric label="Available USDC" value={token(@staking.wallet_usdc_balance, "USDC")} />
            <.metric label="Staked REGENT" value={token(@staking.wallet_stake_balance, "REGENT")} />
            <.metric label="USDC rewards" value={token(@staking.wallet_claimable_usdc, "USDC")} />
            <.metric label="REGENT rewards" value={token(@staking.wallet_claimable_regent, "REGENT")} />
          </dl>
        </section>

        <nav class="regent-ops-actions" aria-label="Regents Labs actions">
          <.link patch="/stake">Stake REGENT</.link>
          <.link patch="/redeem">Redeem Animata</.link>
          <.link :if={@account_control.profile_path} patch={@account_control.profile_path}>
            View Regent profile
          </.link>
        </nav>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="regent-ops-metric">
      <dt>{@label}</dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  defp token(nil, _symbol), do: "—"
  defp token(value, symbol), do: "#{value} #{symbol}"

  defp short_wallet("0x" <> address) when byte_size(address) == 40,
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short_wallet(_wallet), do: "No verified wallet"
end
