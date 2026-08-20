defmodule AshPlatformWeb.StakeLive do
  @moduledoc false
  use Phoenix.Component

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :authenticated, :boolean, required: true
  attr :wallet, :string, default: nil
  attr :action, :string, required: true
  attr :amount, :string, required: true
  attr :notice, :map, default: nil
  attr :prepared, :map, default: nil
  attr :submission, :map, default: nil
  attr :signing, :boolean, default: false
  attr :verifying, :boolean, default: false

  def page(assigns) do
    ~H"""
    <section id="regent-staking" phx-hook="StakeWallet" class="stake-page">
      <header class="stake-heading">
        <p class="stake-kicker">Regents Labs · Base</p>
        <h1>Stake REGENT</h1>
        <p>Stake <span class="stake-mono">$REGENT</span>. Follow the shared revenue rail.</p>
      </header>

      <div :if={@status == :loading} class="stake-status" aria-busy="true">
        Loading staking details…
      </div>
      <div :if={@status == :error} class="stake-status" role="alert">
        Staking details are unavailable right now. Try again shortly.
      </div>

      <div :if={@status == :ready && @staking} class="stake-layout">
        <section class="stake-summary" aria-label="Staking summary">
          <.metric label="Total staked" value={regent(@staking.total_staked)} />
          <.metric :if={@wallet} label="Your wallet" value={regent(@staking.wallet_token_balance)} />
          <.metric :if={@wallet} label="Your stake" value={regent(@staking.wallet_stake_balance)} />
          <.metric
            :if={@wallet}
            label="USDC available"
            value={usdc(@staking.wallet_claimable_usdc)}
          />
          <.metric
            :if={@wallet}
            label="REGENT earned"
            value={regent(@staking.wallet_claimable_regent)}
          />
          <.metric
            :if={@wallet}
            label="REGENT currently funded"
            value={regent(@staking.wallet_funded_claimable_regent)}
          />
        </section>

        <section :if={!@authenticated} class="stake-actions">
          <h2>Connect your account</h2>
          <p>Sign in with the wallet you use for REGENT to stake or claim rewards.</p>
          <button type="button" data-account-target="sign-in">Sign in to stake</button>
        </section>

        <section :if={@authenticated && !@wallet} class="stake-actions" aria-label="Choose a wallet">
          <h2>Choose your wallet</h2>
          <.notice :if={@notice} notice={@notice} />
          <p>
            Pick the wallet you want to stake from. Its balances and rewards appear here once it
            is active.
          </p>
          <button type="button" data-stake-connect>Connect or switch wallet</button>
        </section>

        <section
          :if={@authenticated && @wallet}
          class="stake-actions"
          aria-label="Staking actions"
        >
          <.notice :if={@notice} notice={@notice} />

          <p :if={earned_but_unfunded?(@staking)} class="stake-notice" role="status">
            REGENT rewards are recorded, but the currently funded reward inventory is not enough
            to claim or reinvest them yet.
          </p>

          <section :if={@submission} class="stake-submission" aria-label="Submitted transaction">
            <p :if={@submission[:approval_transaction_hash]}>
              Approval transaction: <.transaction hash={@submission.approval_transaction_hash} />
            </p>
            <p :if={@submission[:transaction_hash]}>
              Staking transaction: <.transaction hash={@submission.transaction_hash} />
            </p>
            <button
              :if={
                signable?(@prepared, @wallet) && @submission[:approval_transaction_hash] &&
                  !@submission[:transaction_hash] && @submission.status == :approval_verified
              }
              type="button"
              data-stake-confirm={@prepared.action_id}
              data-stake-signer={@prepared.expected_signer}
              disabled={@signing}
            >
              {if @signing, do: "Checking approval", else: "Continue after approval"}
            </button>
            <button
              :if={
                @prepared && @submission[:approval_transaction_hash] &&
                  @submission.status == :approval_pending
              }
              type="button"
              phx-click="retry_staking_approval_verification"
              disabled={@signing}
            >
              Retry approval verification
            </button>
            <button
              :if={
                @prepared && @submission[:approval_transaction_hash] &&
                  !@submission[:transaction_hash]
              }
              type="button"
              phx-click="abandon_staking_approval"
            >
              Abandon approval
            </button>
            <p :if={
              @prepared && @submission[:approval_transaction_hash] &&
                !@submission[:transaction_hash] && @submission.status == :approval_verified
            }>
              Abandoning will not send the staking transaction. The approval transaction was
              confirmed on Base, but we have not re-read the current REGENT allowance.
            </p>
            <p :if={
              @prepared && @submission[:approval_transaction_hash] &&
                !@submission[:transaction_hash] && @submission.status == :approval_pending
            }>
              Abandoning will not send the staking transaction. The approval transaction may still
              confirm later; check it in your wallet or on Base.
            </p>
            <button
              :if={@prepared && @submission[:transaction_hash] && @submission.status != :confirmed}
              type="button"
              phx-click="retry_staking_confirmation"
            >
              Retry verification
            </button>
          </section>

          <div class="stake-mode" role="group" aria-label="Stake or unstake">
            <button
              :for={mode <- ~w(stake unstake)}
              type="button"
              phx-click="select_staking_action"
              phx-value-mode={mode}
              aria-pressed={to_string(@action == mode)}
              disabled={pending?(@submission)}
            >
              {mode_label(mode)}
            </button>
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
                disabled={pending?(@submission) or div(balance(@staking, @action), 2) == 0}
              >
                50%
              </button>
              <button
                type="button"
                phx-click="fill_staking_amount"
                phx-value-portion="max"
                disabled={pending?(@submission) or balance(@staking, @action) == 0}
              >
                Max
              </button>
            </div>
            <p class="stake-available">
              Available {regent(available(@staking, @action))}
            </p>
            <button
              class="stake-primary"
              type="button"
              phx-click="prepare_staking"
              phx-value-action={@action}
              disabled={
                pending?(@submission) or String.trim(@amount) == "" or
                  (@action == "stake" and @staking.paused)
              }
            >
              Review {@action}
            </button>
          </form>

          <div class="stake-button-row">
            <button
              type="button"
              phx-click="prepare_staking"
              phx-value-action="claim_usdc"
              disabled={pending?(@submission) or atomic(@staking.wallet_claimable_usdc_raw) == 0}
            >
              Review USDC claim
            </button>
            <button
              type="button"
              phx-click="prepare_staking"
              phx-value-action="claim_regent"
              disabled={pending?(@submission) or !claimable_regent?(@staking)}
            >
              Review REGENT claim
            </button>
            <button
              type="button"
              phx-click="prepare_staking"
              phx-value-action="claim_and_restake_regent"
              disabled={pending?(@submission) or !claimable_regent?(@staking)}
            >
              Review claim and restake
            </button>
          </div>

          <div class="stake-footer">
            <button type="button" phx-click="refresh_staking" disabled={@verifying}>
              Refresh
            </button>
            <a href="/redeem">Redeem an Animata token</a>
          </div>

          <section :if={@prepared} class="stake-review" aria-label="Wallet action review">
            <p class="stake-kicker">Review before signing</p>
            <h2>{action_label(@prepared.action)}</h2>
            <p>{@prepared.risk_copy}</p>
            <dl>
              <div :if={@prepared.arguments[:amount_atomic]}>
                <dt>Amount</dt><dd>{token_amount(@prepared.arguments[:amount_atomic])} REGENT</dd>
              </div>
              <div>
                <dt>Network</dt><dd>Base</dd>
              </div>
              <div>
                <dt>Wallet</dt>
                <dd>
                  <span class="stake-mono">{short(@prepared.expected_signer)}</span>
                  <button
                    type="button"
                    data-copy-signer={@prepared.expected_signer}
                    aria-label="Copy the full wallet address"
                  >
                    Copy
                  </button>
                </dd>
              </div>
              <div>
                <dt>Contract</dt><dd class="stake-mono">{short(@prepared.to)}</dd>
              </div>
              <div>
                <dt>Native value</dt><dd>0 ETH</dd>
              </div>
            </dl>
            <p :if={@prepared.approval}>
              Your wallet may first request an exact REGENT approval for this stake.
            </p>
            <p :if={!signable?(@prepared, @wallet)} role="status">
              This review belongs to another wallet. Switch back to it to finish or dismiss the
              request there.
            </p>
            <button
              :if={!@submission && signable?(@prepared, @wallet)}
              type="button"
              data-stake-confirm={@prepared.action_id}
              data-stake-signer={@prepared.expected_signer}
              disabled={@signing}
            >
              {if @signing, do: "Waiting for wallet", else: "Confirm in wallet"}
            </button>
          </section>
        </section>
      </div>
    </section>
    """
  end

  @doc "The exact decimal REGENT rendering of an atomic amount, never rounded up."
  def token_amount(value) do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, 18)))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  @doc "The exact raw balance the chosen action spends, or zero when it is unavailable."
  def balance(%{wallet_token_balance_raw: amount}, "stake"), do: atomic(amount)
  def balance(%{wallet_stake_balance_raw: amount}, "unstake"), do: atomic(amount)
  def balance(_unread, _action), do: 0

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="stake-metric">
      <dt>{@label}</dt><dd>{@value}</dd>
    </div>
    """
  end

  attr :hash, :string, required: true

  defp transaction(assigns) do
    assigns = assign(assigns, :url, explorer_url(assigns.hash))

    ~H"""
    <a :if={@url} class="stake-mono" href={@url} target="_blank" rel="noopener">
      {short_hash(@hash)}
    </a>
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

  defp regent(nil), do: "—"
  defp regent(value), do: value <> " REGENT"
  defp usdc(nil), do: "—"
  defp usdc(value), do: value <> " USDC"

  defp available(%{wallet_token_balance: value}, "stake"), do: value
  defp available(%{wallet_stake_balance: value}, "unstake"), do: value

  defp short("0x" <> address),
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp mode_label("stake"), do: "Stake"
  defp mode_label("unstake"), do: "Unstake"

  defp action_label("stake"), do: "Stake REGENT"
  defp action_label("unstake"), do: "Unstake REGENT"
  defp action_label("claim_usdc"), do: "Claim USDC"
  defp action_label("claim_regent"), do: "Claim REGENT"
  defp action_label("claim_and_restake_regent"), do: "Claim and restake REGENT"

  # Only the wallet a review was prepared for may open that wallet, so a review
  # left by another wallet stays visible for recovery without a signing control.
  defp signable?(%{expected_signer: signer}, wallet), do: signer == wallet
  defp signable?(_prepared, _wallet), do: false

  defp claimable_regent?(staking) do
    earned = atomic(staking.wallet_claimable_regent_raw)
    earned > 0 and atomic(staking.wallet_funded_claimable_regent_raw) >= earned
  end

  defp earned_but_unfunded?(staking) do
    earned = atomic(staking.wallet_claimable_regent_raw)
    earned > 0 and atomic(staking.wallet_funded_claimable_regent_raw) < earned
  end

  defp atomic(value) do
    case Integer.parse(value || "") do
      {amount, ""} -> amount
      _unavailable -> 0
    end
  end

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"

  # Only the one canonical hash shape becomes a link to the Base explorer.
  defp explorer_url(hash) do
    if String.match?(hash, ~r/\A0x[0-9a-fA-F]{64}\z/), do: "https://basescan.org/tx/" <> hash
  end

  defp pending?(%{status: status}), do: status != :confirmed
  defp pending?(nil), do: false
end
