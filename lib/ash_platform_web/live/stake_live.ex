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
    assigns = assign(assigns, :dashboard, staking_dashboard(assigns.staking))

    ~H"""
    <section
      id="regent-staking"
      phx-hook="StakeWallet"
      class="stake-page"
      data-staking-chain-id={@staking && @staking.chain_id}
      data-staking-signer={@wallet}
      data-staking-allowance={@wallet && stake_allowance(@staking)}
    >
      <header class="stake-heading">
        <p class="stake-kicker">Public contract dashboard · Base</p>
        <h1 id="staking-page-heading" tabindex="-1">REGENT staking</h1>
        <p>
          Explore the latest safe snapshot of the REGENT staking contract. Public contract data is available without signing in.
        </p>
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
        <section class="stake-overview" aria-labelledby="staking-overview-heading">
          <div class="stake-overview-heading">
            <div>
              <p
                class="stake-contract-status"
                data-state={if @staking.paused, do: "paused", else: "active"}
              >
                <span aria-hidden="true"></span>
                {if @staking.paused, do: "Staking paused", else: "Staking active"}
              </p>
              <h2 id="staking-overview-heading">Total staked</h2>
            </div>
            <span class="stake-network">Base</span>
          </div>

          <p class="stake-total">
            <strong>{@dashboard.total_staked}</strong>
            <span>REGENT</span>
          </p>

          <div class="stake-capacity">
            <div class="stake-capacity-heading">
              <span>Capacity utilization</span>
              <strong>{@dashboard.utilization.label}</strong>
            </div>
            <progress
              id="staking-utilization"
              max="100"
              value={@dashboard.utilization.value}
              aria-label="Staking capacity utilization"
            >
              {@dashboard.utilization.label}
            </progress>
            <dl class="stake-capacity-facts">
              <div>
                <dt>Contract capacity</dt>
                <dd>{@dashboard.capacity} REGENT</dd>
              </div>
              <div>
                <dt>Remaining capacity</dt>
                <dd>{@dashboard.remaining_capacity} REGENT</dd>
              </div>
            </dl>
          </div>

          <p class="stake-snapshot-note">
            Snapshot confirmed at Base safe block #{format_number(@staking.block_number)}.
          </p>
        </section>

        <section :if={!@authenticated} class="stake-actions stake-wallet-access">
          <p class="stake-section-kicker">Optional wallet access</p>
          <h2>Connect when you’re ready</h2>
          <p>
            Browsing contract data needs no sign-in. Connect only to view wallet balances or take a staking action.
          </p>
          <button type="button" data-account-target="sign-in">Sign in for wallet access</button>
        </section>
        <section :if={@authenticated && !@wallet} class="stake-actions" aria-label="Choose a wallet">
          <p class="stake-section-kicker">Wallet access</p>
          <h2>Choose your wallet</h2>
          <p>Connect a linked wallet to see its balances and available actions.</p>
          <.notice :if={@notice} notice={@notice} /><button
            type="button"
            data-stake-connect
          >Connect or switch wallet</button>
        </section>

        <section :if={@authenticated && @wallet} class="stake-actions" aria-label="Staking actions">
          <p class="stake-section-kicker">Connected wallet</p>
          <h2>Wallet balances and actions</h2>
          <dl class="stake-wallet-summary">
            <.metric
              label="Wallet balance"
              amount={@staking.wallet_token_balance}
              unit="REGENT"
            />
            <.metric
              label="Wallet stake"
              amount={@staking.wallet_stake_balance}
              unit="REGENT"
            />
            <.metric
              label="Claimable USDC"
              amount={@staking.wallet_claimable_usdc}
              unit="USDC"
            />
            <.metric
              label="Claimable REGENT"
              amount={@staking.wallet_claimable_regent}
              unit="REGENT"
            />
          </dl>
          <.notice :if={@notice} notice={@notice} />
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

        <section class="stake-contract-details" aria-labelledby="staking-contract-heading">
          <div class="stake-section-heading">
            <div>
              <p class="stake-section-kicker">Onchain details</p>
              <h2 id="staking-contract-heading">Contract details</h2>
            </div>
            <a
              class="stake-contract-link"
              href={@dashboard.basescan_url}
              target="_blank"
              rel="noopener noreferrer"
            >
              View verified staking contract on BaseScan <span aria-hidden="true">↗</span>
            </a>
          </div>
          <dl class="stake-contract-facts">
            <div>
              <dt>Base staking contract</dt>
              <dd><code>{@staking.contract_address}</code></dd>
            </div>
            <div>
              <dt>REGENT token</dt>
              <dd><code>{@staking.stake_token_address}</code></dd>
            </div>
            <div>
              <dt>USDC reward token</dt>
              <dd><code>{@staking.usdc_address}</code></dd>
            </div>
            <div>
              <dt>Safe Base block</dt>
              <dd>
                <span>#{format_number(@staking.block_number)}</span>
                <code>{@staking.block_hash}</code>
              </dd>
            </div>
          </dl>
        </section>

        <section class="stake-how-it-works" aria-labelledby="staking-explainer-heading">
          <p class="stake-section-kicker">The essentials</p>
          <h2 id="staking-explainer-heading">How staking works</h2>
          <p>
            Stake REGENT to participate in reward tokens distributed by the contract. Your portion is proportional to your share of the total REGENT staked at the time rewards are accounted for.
          </p>
          <p>
            A connected wallet is needed only to see its position, stake or unstake REGENT, and claim eligible USDC or REGENT rewards.
          </p>
        </section>
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

  defp staking_dashboard(nil), do: nil

  defp staking_dashboard(staking) do
    %{
      basescan_url: "https://basescan.org/address/#{staking.contract_address}",
      capacity: staking.supply_denominator_raw |> token_amount() |> format_number(),
      remaining_capacity: format_number(staking.remaining_capacity),
      total_staked: format_number(staking.total_staked),
      utilization: utilization(staking.total_staked_raw, staking.supply_denominator_raw)
    }
  end

  defp utilization(total_raw, denominator_raw) do
    total = Decimal.new(total_raw)
    denominator = Decimal.new(denominator_raw)

    percentage =
      if Decimal.positive?(denominator) do
        total
        |> Decimal.mult(100)
        |> Decimal.div(denominator)
        |> Decimal.round(2)
        |> Decimal.normalize()
      else
        Decimal.new(0)
      end

    progress_value =
      cond do
        Decimal.negative?(percentage) -> Decimal.new(0)
        Decimal.gt?(percentage, 100) -> Decimal.new(100)
        true -> percentage
      end

    %{
      label: "#{Decimal.to_string(percentage, :normal)}%",
      value: Decimal.to_string(progress_value, :normal)
    }
  end

  defp format_number(value) when is_integer(value),
    do: value |> Integer.to_string() |> format_number()

  defp format_number(value) do
    case String.split(value, ".", parts: 2) do
      [whole] -> delimit_whole(whole)
      [whole, fraction] -> "#{delimit_whole(whole)}.#{fraction}"
    end
  end

  defp delimit_whole(whole), do: Regex.replace(~r/\B(?=(\d{3})+(?!\d))/, whole, ",")

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
