defmodule AshPlatformWeb.StakeLive do
  @moduledoc false
  use Phoenix.Component
  alias AshPlatformWeb.TokenDisplay

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :wallet, :string, default: nil
  attr :action, :string, required: true
  attr :amount, :string, required: true
  attr :notice, :map, default: nil
  attr :reading, :boolean, default: false
  attr :spendable, :integer, default: 0
  attr :amount_notice, :string, default: nil
  attr :available_claims, :map, default: %{}

  @claims [
    {"claim_usdc", "Claim USDC"},
    {"claim_regent", "Claim REGENT"},
    {"claim_and_restake_regent", "Claim and restake"}
  ]

  def page(assigns) do
    claims = claims(assigns.available_claims)

    assigns =
      assigns
      |> assign(:dashboard, staking_dashboard(assigns.staking))
      |> assign(:wallet_ready, wallet_ready?(assigns.staking, assigns.wallet))
      |> assign(:preview, position_preview(assigns))
      |> assign(:claims, claims)
      |> assign(:claim_hints, Enum.filter(claims, & &1.hint))

    ~H"""
    <section
      id="regent-staking"
      phx-hook="StakeWallet"
      class="stake-page"
      aria-busy={to_string(@reading)}
      data-staking-chain-id={@staking && @staking.chain_id}
      data-staking-signer={@wallet}
      data-staking-allowance={@wallet && stake_allowance(@staking)}
    >
      <header class="stake-heading">
        <div class="stake-heading-copy">
          <p class="stake-kicker">REGENT staking · Base</p>
          <h1 id="staking-page-heading" tabindex="-1">Put REGENT to work.</h1>
          <p class="stake-lede">
            Stake REGENT to participate in contract-distributed USDC revenue rewards and REGENT emissions. Explore the live contract before connecting a wallet.
          </p>
          <div class="stake-heading-actions">
            <button :if={!@wallet} type="button" class="stake-primary" data-stake-connect>
              Connect wallet to stake
            </button>
            <a href="#staking-contract-overview">Explore contract data</a>
          </div>
          <p class="stake-auth-note">No Regent account or Privy login is required.</p>
        </div>

        <dl :if={@dashboard} class="stake-benefit-grid" aria-label="Current staking benefits">
          <div class="stake-benefit-card stake-benefit-card-primary">
            <dt>REGENT emissions APR</dt>
            <dd>{@dashboard.emission_apr}</dd>
            <p>Current rate set by the staking contract.</p>
          </div>
          <div class="stake-benefit-card">
            <dt>USDC reserved</dt>
            <dd>{@dashboard.reserved_usdc}</dd>
            <p>USDC currently reserved for staker rewards.</p>
          </div>
          <div class="stake-benefit-card">
            <dt>REGENT reward inventory</dt>
            <dd>{@dashboard.available_regent_rewards}</dd>
            <p>Reward inventory currently available onchain.</p>
          </div>
        </dl>
      </header>

      <div
        id="staking-transaction-progress"
        class="stake-transaction-progress"
        data-staking-progress
        data-phase="idle"
        role="status"
        aria-live="polite"
        aria-atomic="true"
        phx-update="ignore"
        hidden
      >
        <span class="stake-progress-mark" aria-hidden="true"></span>
        <div>
          <strong data-staking-progress-title></strong>
          <p data-staking-progress-copy></p>
        </div>
      </div>

      <dialog
        id="staking-result-dialog"
        class="stake-result-dialog"
        aria-labelledby="staking-result-heading"
        phx-update="ignore"
      >
        <p class="stake-dialog-kicker">Base transaction receipt</p>
        <h2 id="staking-result-heading" data-staking-result-title>Transaction update</h2>
        <p class="stake-dialog-summary" data-staking-result-text></p>
        <p class="stake-dialog-detail" data-staking-result-detail></p>
        <dl class="stake-dialog-meta">
          <div>
            <dt>Network</dt><dd>Base</dd>
          </div>
          <div>
            <dt>Wallet</dt><dd data-staking-result-wallet>—</dd>
          </div>
        </dl>
        <a data-staking-result-link hidden target="_blank" rel="noopener noreferrer"></a>
        <form method="dialog">
          <button type="submit" value="close">Done</button>
        </form>
      </dialog>

      <div :if={@status == :loading} class="stake-status" aria-busy="true">
        Loading staking contract data…
      </div>
      <div :if={@status == :error} class="stake-status">
        <p role="alert">Staking details are unavailable right now.</p>
        <button type="button" phx-click="refresh_staking" disabled={@reading}>Try again</button>
      </div>

      <div :if={@status == :ready && @staking} class="stake-layout">
        <section class="stake-actions" aria-labelledby="staking-actions-heading">
          <div class="stake-section-heading">
            <div>
              <p class="stake-section-kicker">Your next move</p>
              <h2 id="staking-actions-heading">
                {if @wallet, do: "Manage your stake", else: "Stake in three steps"}
              </h2>
            </div>
            <span :if={@wallet} class="stake-signer" title={@wallet}>
              <span aria-hidden="true"></span>{short_wallet(@wallet)}
            </span>
          </div>

          <div :if={!@wallet} class="stake-connect-flow">
            <ol>
              <li>
                <span>1</span><p><strong>Connect</strong> an Ethereum wallet through Privy.</p>
              </li>
              <li>
                <span>2</span><p><strong>Choose</strong> how much REGENT to stake.</p>
              </li>
              <li>
                <span>3</span><p><strong>Confirm</strong> each Base transaction in your wallet.</p>
              </li>
            </ol>
            <button type="button" class="stake-primary" data-stake-connect>Connect wallet</button>
            <p class="stake-fine-print">
              Connecting a wallet does not create a Regent account. Nothing is sent without your wallet confirmation.
            </p>
          </div>

          <.notice :if={@wallet && @notice} notice={@notice} />

          <div :if={@wallet && !@wallet_ready && @reading} class="stake-wallet-loading" role="status">
            <span class="stake-progress-mark" aria-hidden="true"></span>
            <p>Loading this wallet’s position while contract data remains on screen…</p>
          </div>

          <div :if={@wallet && !@wallet_ready && !@reading} class="stake-wallet-recovery">
            <p>Your wallet is connected, but its latest Base position could not be loaded.</p>
            <div>
              <button type="button" phx-click="refresh_staking">Try again</button>
              <button type="button" data-stake-connect>Switch wallet</button>
            </div>
          </div>

          <div :if={@wallet_ready} class="stake-wallet-controls">
            <dl class="stake-wallet-summary">
              <.metric label="Available REGENT" amount={@staking.wallet_token_balance} unit="REGENT" />
              <.metric label="Currently staked" amount={@staking.wallet_stake_balance} unit="REGENT" />
              <.metric label="Claimable USDC" amount={@staking.wallet_claimable_usdc} unit="USDC" />
              <.metric
                label="Claimable REGENT"
                amount={@staking.wallet_claimable_regent}
                unit="REGENT"
              />
            </dl>

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
              <label for="staking-amount">Amount</label>
              <div class="stake-amount">
                <input
                  id="staking-amount"
                  name="amount"
                  value={@amount}
                  inputmode="decimal"
                  autocomplete="off"
                  placeholder="0.0"
                  aria-describedby="staking-available staking-amount-feedback"
                />
                <span>REGENT</span>
              </div>
              <div class="stake-amount-tools">
                <p id="staking-available">Available {token_amount(@spendable)} REGENT</p>
                <div>
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
              </div>
              <p
                id="staking-amount-feedback"
                class="stake-amount-notice"
                role="status"
                data-visible={to_string(not is_nil(@amount_notice))}
              >
                {@amount_notice}
              </p>

              <dl :if={@preview} class="stake-preview" aria-label="Estimated position after action">
                <div>
                  <dt>Position after</dt><dd>{@preview.position} REGENT</dd>
                </div>
                <div>
                  <dt>Pool share after</dt><dd>{@preview.share}</dd>
                </div>
              </dl>

              <p :if={approval_needed?(@staking, @action, @amount)} class="stake-approval-note">
                Your wallet will first request an exact REGENT approval, then the stake transaction.
              </p>
              <button
                class="stake-primary stake-submit"
                type="button"
                data-staking-action={@action}
              >{mode_label(@action)} REGENT</button>
            </form>

            <section class="stake-rewards" aria-labelledby="staking-rewards-heading">
              <div>
                <p class="stake-section-kicker">Available rewards</p>
                <h3 id="staking-rewards-heading">Claim or compound</h3>
              </div>
              <div class="stake-button-row">
                <button
                  :for={claim <- @claims}
                  type="button"
                  data-staking-action={claim.action}
                  aria-describedby={claim.hint_id}
                >{claim.label}</button>
              </div>
              <p :for={claim <- @claim_hints} id={claim.hint_id} class="stake-fine-print">
                {claim.label} — {claim.hint}
              </p>
            </section>

            <div class="stake-footer">
              <button type="button" phx-click="refresh_staking" disabled={@reading}>
                {if @reading, do: "Updating…", else: "Refresh position"}
              </button>
              <button type="button" data-stake-connect>Switch wallet</button>
            </div>
          </div>
        </section>

        <section
          id="staking-contract-overview"
          class="stake-overview"
          aria-labelledby="staking-overview-heading"
        >
          <div class="stake-overview-heading">
            <div>
              <p
                class="stake-contract-status"
                data-state={if @staking.paused, do: "paused", else: "active"}
              >
                <span aria-hidden="true"></span>{if @staking.paused,
                  do: "Staking paused",
                  else: "Staking active"}
              </p>
              <h2 id="staking-overview-heading">Live contract position</h2>
            </div>
            <span class="stake-network">Base</span>
          </div>

          <p class="stake-total">
            <strong>{@dashboard.total_staked}</strong><span>REGENT staked</span>
          </p>

          <div class="stake-capacity">
            <div class="stake-capacity-heading">
              <span>Capacity utilization</span><strong>{@dashboard.utilization.label}</strong>
            </div>
            <progress
              id="staking-utilization"
              max="100"
              value={@dashboard.utilization.value}
              aria-label="Staking capacity utilization"
            >{@dashboard.utilization.label}</progress>
            <dl class="stake-capacity-facts">
              <div>
                <dt>Contract capacity</dt><dd>{@dashboard.capacity} REGENT</dd>
              </div>
              <div>
                <dt>Capacity remaining</dt><dd>{@dashboard.remaining_capacity} REGENT</dd>
              </div>
            </dl>
          </div>

          <p class="stake-snapshot-note">
            <span>Confirmed at Base block #{format_number(@staking.block_number)}.</span>
            <span :if={@reading} class="stake-inline-loading"> Updating from Base…</span>
          </p>
        </section>

        <section class="stake-how-it-works" aria-labelledby="staking-explainer-heading">
          <div>
            <p class="stake-section-kicker">Why stake</p>
            <h2 id="staking-explainer-heading">One position, two reward sources</h2>
          </div>
          <article>
            <span aria-hidden="true">01</span><h3>USDC revenue rewards</h3><p>
              Eligible USDC deposited into the contract is accounted across stakers according to stake share.
            </p>
          </article>
          <article>
            <span aria-hidden="true">02</span><h3>REGENT emissions</h3><p>
              The contract currently reports a {@dashboard.emission_apr} emissions APR, subject to onchain changes and available inventory.
            </p>
          </article>
          <article>
            <span aria-hidden="true">03</span><h3>You stay in control</h3><p>
              Stake, unstake, claim, or compound through the connected wallet. Every transaction requires your signature.
            </p>
          </article>
        </section>

        <details class="stake-contract-details">
          <summary>
            <span><span class="stake-section-kicker">Verification</span> Contract and snapshot details</span>
            <span aria-hidden="true">+</span>
          </summary>
          <div class="stake-contract-details-body">
            <a
              class="stake-contract-link"
              href={@dashboard.basescan_url}
              target="_blank"
              rel="noopener noreferrer"
            >View verified staking contract on BaseScan <span aria-hidden="true">↗</span></a>
            <dl class="stake-contract-facts">
              <div>
                <dt>Staking contract</dt><dd><code>{@staking.contract_address}</code></dd>
              </div>
              <div>
                <dt>REGENT token</dt><dd><code>{@staking.stake_token_address}</code></dd>
              </div>
              <div>
                <dt>USDC token</dt><dd><code>{@staking.usdc_address}</code></dd>
              </div>
              <div>
                <dt>Base block</dt><dd>
                  <span>#{format_number(@staking.block_number)}</span><code>{@staking.block_hash}</code>
                </dd>
              </div>
            </dl>
          </div>
        </details>
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
      available_regent_rewards:
        "#{format_number(Map.get(staking, :available_regent_reward_inventory, "0"))} REGENT",
      reserved_usdc: "#{format_number(Map.get(staking, :reserved_usdc, "0"))} USDC",
      emission_apr: "#{format_number(Map.get(staking, :emission_apr_percent, "0"))}%",
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

  defp position_preview(%{staking: nil}), do: nil

  defp position_preview(%{staking: staking, action: action, amount: amount}) do
    with {:ok, requested} <- AshPlatform.Staking.parse_amount(amount),
         {:ok, current_position} <- atomic(staking.wallet_stake_balance_raw),
         {:ok, total} <- atomic(staking.total_staked_raw) do
      {position, pool} =
        if action == "stake",
          do: {current_position + requested, total + requested},
          else: {max(current_position - requested, 0), max(total - requested, 0)}

      %{
        position: position |> token_amount() |> format_number(),
        share: percentage(position, pool)
      }
    else
      _ -> nil
    end
  end

  # Every claim control is offered. The last reading from Base only supplies the
  # sentence beside it, so a customer knows what that reading found before the
  # contract answers for itself.
  defp claims(available) do
    for {action, label} <- @claims do
      hint = claim_hint(Map.get(available, action))
      %{action: action, label: label, hint: hint, hint_id: hint && "staking-claim-hint-#{action}"}
    end
  end

  defp claim_hint(nil), do: nil
  defp claim_hint(:no_claimable_usdc), do: "no USDC rewards in the last reading from Base."

  defp claim_hint(:no_regent_rewards),
    do: "no REGENT rewards accrued in the last reading from Base."

  defp claim_hint(:regent_rewards_not_funded),
    do:
      "the funded REGENT reward inventory is below what is claimable in the last reading from Base."

  defp claim_hint(:staking_paused), do: "staking shows as paused in the last reading from Base."

  defp claim_hint(:amount_above_capacity),
    do:
      "restaking the claimable REGENT exceeds the capacity the contract can still take in the last reading from Base."

  defp claim_hint(:chain_unavailable), do: "the last reading from Base is unavailable."

  defp wallet_ready?(staking, wallet) when is_map(staking) and is_binary(wallet),
    do: Map.get(staking, :wallet_address) == wallet

  defp wallet_ready?(_, _), do: false

  defp approval_needed?(staking, "stake", amount) when is_map(staking) do
    with {:ok, requested} <- AshPlatform.Staking.parse_amount(amount),
         {:ok, allowance} <- atomic(Map.get(staking, :wallet_stake_allowance_raw)) do
      allowance < requested
    else
      _ -> false
    end
  end

  defp approval_needed?(_, _, _), do: false
  defp percentage(_part, 0), do: "0%"

  defp percentage(part, whole) do
    part
    |> Decimal.new()
    |> Decimal.mult(100)
    |> Decimal.div(Decimal.new(whole))
    |> Decimal.round(4)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> Kernel.<>("%")
  end

  defp atomic(value) when is_binary(value) do
    case Integer.parse(value) do
      {amount, ""} -> {:ok, amount}
      _ -> :error
    end
  end

  defp atomic(_), do: :error

  defp short_wallet("0x" <> address) when byte_size(address) == 40,
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short_wallet(wallet), do: wallet

  defp format_number(value) when is_integer(value),
    do: value |> Integer.to_string() |> format_number()

  defp format_number(value) when is_binary(value) do
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
