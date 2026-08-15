defmodule AshPlatformWeb.StakeLive do
  @moduledoc false
  use Phoenix.Component

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :authenticated, :boolean, required: true
  attr :amount, :string, required: true
  attr :notice, :map, default: nil
  attr :prepared, :map, default: nil
  attr :submission, :map, default: nil
  attr :signing, :boolean, default: false

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
          <.metric label="Your wallet" value={regent(@staking.wallet_token_balance)} />
          <.metric label="Your stake" value={regent(@staking.wallet_stake_balance)} />
          <.metric label="USDC available" value={usdc(@staking.wallet_claimable_usdc)} />
          <.metric label="REGENT earned" value={regent(@staking.wallet_claimable_regent)} />
          <.metric
            label="REGENT currently funded"
            value={regent(@staking.wallet_funded_claimable_regent)}
          />
        </section>

        <section :if={!@authenticated} class="stake-actions">
          <h2>Connect your account</h2>
          <p>Sign in with the wallet you use for REGENT to stake or claim rewards.</p>
          <button type="button" data-account-target="sign-in">Sign in to stake</button>
        </section>

        <section :if={@authenticated} class="stake-actions" aria-label="Staking actions">
          <.notice :if={@notice} notice={@notice} />

          <p :if={!regent_rewards_funded?(@staking)} class="stake-notice" role="status">
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
                @prepared && @submission[:approval_transaction_hash] &&
                  !@submission[:transaction_hash] && @submission.status == :approval_verified
              }
              type="button"
              phx-click="sign_prepared_staking"
              phx-value-action-id={@prepared.action_id}
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
              Abandoning will not send the staking transaction. Approval transaction {short_hash(
                @submission.approval_transaction_hash
              )} may still confirm later; check it
              in your wallet or on Base.
            </p>
            <button
              :if={@prepared && @submission[:transaction_hash] && @submission.status != :confirmed}
              type="button"
              phx-click="retry_staking_confirmation"
            >
              Retry verification
            </button>
            <button :if={@submission.status == :confirmed} type="button" phx-click="refresh_staking">
              Refresh staking details
            </button>
          </section>

          <form id="staking-amount-form" phx-change="staking_amount_changed">
            <label for="staking-amount">REGENT amount</label>
            <input
              id="staking-amount"
              name="amount"
              value={@amount}
              inputmode="decimal"
              autocomplete="off"
              placeholder="0.0"
            />
            <div class="stake-button-row">
              <button
                type="button"
                phx-click="prepare_staking"
                phx-value-action="stake"
                disabled={pending?(@submission) or @staking.paused}
              >
                Review stake
              </button>
              <button
                type="button"
                phx-click="prepare_staking"
                phx-value-action="unstake"
                disabled={pending?(@submission)}
              >
                Review unstake
              </button>
            </div>
          </form>

          <div class="stake-button-row">
            <button
              type="button"
              phx-click="prepare_staking"
              phx-value-action="claim_usdc"
              disabled={pending?(@submission)}
            >
              Review USDC claim
            </button>
            <button
              type="button"
              phx-click="prepare_staking"
              phx-value-action="claim_regent"
              disabled={pending?(@submission) or !regent_rewards_funded?(@staking)}
            >
              Review REGENT claim
            </button>
            <button
              type="button"
              phx-click="prepare_staking"
              phx-value-action="claim_and_restake_regent"
              disabled={pending?(@submission) or !regent_rewards_funded?(@staking)}
            >
              Review claim and restake
            </button>
          </div>

          <section :if={@prepared} class="stake-review" aria-label="Wallet action review">
            <p class="stake-kicker">Review before signing</p>
            <h2>{action_label(@prepared.action)}</h2>
            <p>{@prepared.risk_copy}</p>
            <dl>
              <div :if={@prepared.arguments[:amount_atomic]}>
                <dt>Amount</dt><dd>{format_atomic(@prepared.arguments[:amount_atomic])} REGENT</dd>
              </div>
              <div :if={recipient(@prepared.arguments)}>
                <dt>Recipient</dt><dd class="stake-mono">{short(recipient(@prepared.arguments))}</dd>
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
            <button
              :if={!@submission}
              type="button"
              phx-click="sign_prepared_staking"
              phx-value-action-id={@prepared.action_id}
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

  defp short("0x" <> address),
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp action_label("stake"), do: "Stake REGENT"
  defp action_label("unstake"), do: "Unstake REGENT"
  defp action_label("claim_usdc"), do: "Claim USDC"
  defp action_label("claim_regent"), do: "Claim REGENT"
  defp action_label("claim_and_restake_regent"), do: "Claim and restake REGENT"

  defp regent_rewards_funded?(staking) do
    with {earned, ""} <- Integer.parse(staking.wallet_claimable_regent_raw || "0"),
         {funded, ""} <- Integer.parse(staking.wallet_funded_claimable_regent_raw || "0") do
      earned == 0 or funded >= earned
    else
      _ -> false
    end
  end

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"

  # Only the one canonical hash shape becomes a link to the Base explorer.
  defp explorer_url(hash) do
    if String.match?(hash, ~r/^0x[0-9a-fA-F]{64}$/), do: "https://basescan.org/tx/" <> hash
  end

  defp pending?(%{status: status}), do: status != :confirmed
  defp pending?(nil), do: false

  defp recipient(arguments), do: arguments[:receiver] || arguments[:recipient]

  defp format_atomic(value) do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, 18)))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
