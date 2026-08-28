defmodule AshPlatformWeb.StakeLive do
  @moduledoc false
  use Phoenix.Component
  alias AshPlatformWeb.TokenDisplay

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :authenticated, :boolean, required: true
  attr :wallet, :string, default: nil
  attr :action, :string, required: true
  attr :amount, :string, required: true
  attr :notice, :map, default: nil
  attr :reading, :boolean, default: false
  attr :spendable, :integer, default: 0
  attr :amount_notice, :string, default: nil
  attr :available_claims, :list, default: []

  def page(assigns) do
    ~H"""
    <section
      id="regent-staking"
      phx-hook="StakeWallet"
      class="stake-page"
      data-staking-chain-id={@staking && @staking.chain_id}
      data-staking-signer={@wallet}
      data-staking-allowance={stake_allowance(@staking)}
    >
      <header class="stake-heading">
        <p class="stake-kicker">Regents Labs · Base</p>
        <h1 id="staking-page-heading" tabindex="-1">Stake REGENT</h1>
        <p>Stake $REGENT. Receive revenue tokens equal to your staked percentage.</p>
      </header>

      <dialog
        id="staking-result-dialog"
        class="stake-result-dialog"
        aria-labelledby="staking-result-heading"
        phx-update="ignore"
      >
        <h2 id="staking-result-heading">Staking result</h2>
        <p data-staking-result-text></p>
        <a
          data-staking-result-link
          hidden
          target="_blank"
          rel="noopener noreferrer"
        ></a>
        <form method="dialog">
          <button type="submit" value="close">Close</button>
        </form>
      </dialog>

      <div :if={@status == :loading} class="stake-status" aria-busy="true">
        Loading staking details…
      </div>
      <div :if={@status == :error} class="stake-status">
        <p role="alert">Staking details are unavailable right now.</p>
        <button type="button" phx-click="refresh_staking" disabled={@reading}>Try again</button>
      </div>

      <div :if={@status == :ready && @staking} class="stake-layout">
        <section class="stake-balance-card" aria-label="Staking balances and rewards">
          <div class="stake-network"><span>Network</span><strong>Base</strong></div>
          <dl class="stake-summary">
            <.metric label="Total staked" amount={@staking.total_staked} unit="REGENT" />
            <.metric label="Remaining capacity" amount={@staking.remaining_capacity} unit="REGENT" />
            <.metric
              :if={@wallet}
              label="Wallet balance"
              amount={@staking.wallet_token_balance}
              unit="REGENT"
            />
            <.metric
              :if={@wallet}
              label="Wallet stake"
              amount={@staking.wallet_stake_balance}
              unit="REGENT"
            />
            <.metric
              :if={@wallet}
              label="Claimable USDC"
              amount={@staking.wallet_claimable_usdc}
              unit="USDC"
            />
            <.metric
              :if={@wallet}
              label="Claimable REGENT"
              amount={@staking.wallet_claimable_regent}
              unit="REGENT"
            />
            <.metric
              :if={@wallet}
              label="Currently funded REGENT"
              amount={@staking.wallet_funded_claimable_regent}
              unit="REGENT"
            />
          </dl>
        </section>

        <section :if={!@authenticated} class="stake-actions">
          <h2>Connect your account</h2><p>Sign in with the wallet you use for REGENT.</p>
          <button type="button" data-account-target="sign-in">Sign in to stake</button>
        </section>
        <section :if={@authenticated && !@wallet} class="stake-actions" aria-label="Choose a wallet">
          <h2>Choose your wallet</h2><.notice :if={@notice} notice={@notice} /><button
            type="button"
            data-stake-connect
          >Connect or switch wallet</button>
        </section>

        <section :if={@authenticated && @wallet} class="stake-actions" aria-label="Staking actions">
          <h2>Wallet actions</h2><.notice :if={@notice} notice={@notice} />
          <div class="stake-mode" role="group" aria-label="Stake or unstake">
            <button
              :for={mode <- ~w(stake unstake)}
              type="button"
              phx-click="select_staking_action"
              phx-value-mode={mode}
              aria-pressed={to_string(@action == mode)}
            >{mode_label(mode)}</button>
          </div>
          <form id="staking-amount-form" phx-change="staking_amount_changed">
            <label for="staking-amount">REGENT amount</label>
            <div class="stake-amount">
              <input
                id="staking-amount"
                name="amount"
                value={@amount}
                inputmode="decimal"
                autocomplete="off"
                placeholder="0.0"
              />
              <button
                type="button"
                phx-click="fill_staking_amount"
                phx-value-portion="half"
                disabled={div(@spendable, 2) == 0}
              >50%</button>
              <button
                type="button"
                phx-click="fill_staking_amount"
                phx-value-portion="max"
                disabled={@spendable == 0}
              >Max</button>
            </div>
            <p class="stake-available">Available {token_amount(@spendable)} REGENT</p>
            <p :if={@amount_notice} class="stake-amount-notice" role="status">{@amount_notice}</p>
            <button
              class="stake-primary"
              type="button"
              data-staking-action={@action}
            >{mode_label(@action)}</button>
          </form>
          <div class="stake-button-row">
            <button
              type="button"
              data-staking-action="claim_usdc"
              disabled={"claim_usdc" not in @available_claims}
            >Claim USDC</button>
            <button
              type="button"
              data-staking-action="claim_regent"
              disabled={"claim_regent" not in @available_claims}
            >Claim REGENT</button>
            <button
              type="button"
              data-staking-action="claim_and_restake_regent"
              disabled={"claim_and_restake_regent" not in @available_claims}
            >Claim and restake</button>
          </div>
          <div class="stake-footer">
            <button type="button" phx-click="refresh_staking" disabled={@reading}>Refresh</button><a href="/redeem">Redeem an Animata token</a>
          </div>
        </section>

        <div class="stake-explainers">
          <article>
            <h2>Unstake when you choose</h2><p>
              Unstaking returns the selected amount to your active wallet immediately.
            </p>
          </article>
          <article>
            <h2>Current Base balances</h2><p>
              Balances and rewards are read from Base. Your staked percentage determines your proportional revenue-token participation.
            </p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  def token_amount(value),
    do:
      value
      |> Decimal.new()
      |> Decimal.div(Decimal.new(Integer.pow(10, 18)))
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)

  defp stake_allowance(staking) when is_map(staking),
    do: Map.get(staking, :wallet_stake_allowance_raw, "0")

  defp stake_allowance(_staking), do: nil

  attr :label, :string, required: true
  attr :amount, :string, default: nil
  attr :unit, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="stake-metric">
      <dt>{@label}</dt><dd><TokenDisplay.amount amount={@amount} unit={@unit} /></dd>
    </div>
    """
  end

  attr :notice, :map, required: true

  defp notice(assigns) do
    ~H"""
    <p class="stake-notice" role={if @notice.tone == :error, do: "alert", else: "status"}>
      {@notice.message}
    </p>
    """
  end

  defp mode_label("stake"), do: "Stake"
  defp mode_label("unstake"), do: "Unstake"
end
