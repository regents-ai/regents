defmodule AshPlatformWeb.RedeemLive do
  @moduledoc false
  use Phoenix.Component

  @unavailable_owner "Unable to verify this NFT. Check the collection and token ID."

  @doc """
  The one neutral line for a selected token whose owner could not be read.

  A transport failure and a token that does not exist are indistinguishable, so
  this says only that the selection could not be verified.
  """
  def unavailable_owner_copy, do: @unavailable_owner

  attr :redemption, :map, default: nil
  attr :status, :atom, required: true
  attr :authenticated, :boolean, required: true
  attr :wallet, :string, default: nil
  attr :collection, :string, required: true
  attr :token_id, :string, required: true
  attr :notice, :map, default: nil
  attr :prepared, :map, default: nil
  attr :submission, :map, default: nil
  attr :signing, :boolean, default: false
  attr :step, :atom, default: nil

  def redemption_page(assigns) do
    ~H"""
    <section id="animata-redemption" phx-hook="RedemptionWallet" class="redeem-page">
      <header class="redeem-heading">
        <p class="redeem-kicker">Regents Labs · Base</p>
        <h1>Redeem Animata</h1>
        <p>
          Redeem an Animata I or II token for a Regents Club token and a seven-day stream of
          5,000,000 REGENT.
        </p>
      </header>

      <section class="redeem-facts" aria-label="Redemption facts">
        <.metric label="Cost" value="80 USDC" />
        <.metric label="Reward" value="5,000,000 REGENT" />
        <.metric label="Vesting" value="7 days" />
        <.metric label="Network" value="Base" />
      </section>

      <div :if={@status == :loading} class="redeem-status" aria-busy="true">
        Loading redemption details…
      </div>
      <div :if={@status == :error} class="redeem-status" role="alert">
        Redemption details are unavailable right now. Try again shortly.
      </div>

      <div :if={@status == :ready && @redemption} class="redeem-layout">
        <section class="redeem-summary" aria-label="Redemption account status">
          <.metric label="USDC balance" value={usdc(@redemption.usdc_balance)} />
          <.metric label="USDC allowance" value={usdc(@redemption.usdc_allowance)} />
          <.metric label="Claimable REGENT" value={regent(@redemption.claimable)} />
          <.metric label="Vest total" value={regent(@redemption.vest_pool)} />
          <.metric label="Released" value={regent(@redemption.vest_released)} />
          <.metric label="Claimed" value={regent(@redemption.vest_claimed)} />
          <.metric
            :if={@redemption.result_token_id}
            label="Regents Club"
            value={"Result token ##{@redemption.result_token_id}"}
          />
        </section>

        <section :if={!@authenticated} class="redeem-actions">
          <h2>Connect your account</h2>
          <p>Sign in with the wallet that holds your Animata token to redeem or claim.</p>
          <button type="button" data-account-target="sign-in">Sign in to redeem</button>
        </section>

        <section
          :if={@authenticated && !@wallet}
          class="redeem-actions"
          aria-label="Choose a wallet"
        >
          <h2>Choose your wallet</h2>
          <.notice :if={@notice} notice={@notice} />
          <p>
            Pick the wallet that holds your Animata token. Its balances and vest appear here once
            it is active.
          </p>
          <button type="button" data-redeem-connect>Connect or switch wallet</button>
        </section>

        <section
          :if={@authenticated && @wallet}
          class="redeem-actions"
          aria-label="Redemption actions"
        >
          <.notice :if={@notice} notice={@notice} />

          <form id="redemption-selection" phx-change="redemption_selection_changed">
            <label for="redemption-collection">Collection</label>
            <select
              id="redemption-collection"
              name="collection"
              disabled={locked?(@prepared, @submission)}
            >
              <option value="animata_i" selected={@collection == "animata_i"}>Animata I</option>
              <option value="animata_ii" selected={@collection == "animata_ii"}>Animata II</option>
            </select>
            <label for="redemption-token-id">Token ID</label>
            <input
              id="redemption-token-id"
              name="token_id"
              value={@token_id}
              inputmode="numeric"
              autocomplete="off"
              placeholder="1–999"
              disabled={locked?(@prepared, @submission)}
            />
          </form>

          <p :if={valid_token_input?(@token_id)} class="redeem-selection-status">
            {"#{collection_label(@collection)} · Token ##{@token_id}"}
          </p>
          <p :if={@redemption.nft_owner} class="redeem-selection-status">
            Owner: <span class="redeem-mono">{short(@redemption.nft_owner)}</span>
          </p>

          <section :if={@submission} class="redeem-submission" aria-label="Submitted transaction">
            <p>
              Submitted transaction: <.transaction hash={@submission.transaction_hash} />
            </p>
            <p :if={confirmed_result(@submission)}>{confirmed_result(@submission)}</p>
            <button
              :if={@prepared && @submission.status not in [:confirmed, :unverified]}
              type="button"
              phx-click="retry_redemption_confirmation"
            >
              Retry verification
            </button>
            <button
              :if={@submission.status in [:confirmed, :unverified]}
              type="button"
              phx-click="refresh_redemption"
            >
              Refresh redemption details
            </button>
          </section>

          <section class="redeem-next-step" aria-label="Next step">
            <p class="redeem-kicker">Next step</p>
            <p>{step_label(@step)}</p>
            <button
              type="button"
              phx-click="prepare_redemption"
              phx-value-action={step_action(@step)}
              disabled={locked?(@prepared, @submission) || is_nil(step_action(@step))}
            >
              {step_control(@step)}
            </button>
          </section>

          <div class="redeem-button-row">
            <button
              type="button"
              phx-click="prepare_redemption"
              phx-value-action="claim"
              disabled={locked?(@prepared, @submission) || !claim_ready?(@redemption)}
            >
              Review REGENT claim
            </button>
          </div>

          <section :if={@prepared} class="redeem-review" aria-label="Wallet action review">
            <p class="redeem-kicker">Review before signing</p>
            <h2>{action_label(@prepared.action)}</h2>
            <p>{@prepared.risk_copy}</p>
            <dl>
              <div :if={@prepared.arguments[:collection]}>
                <dt>Selection</dt>
                <dd>{selection(@prepared.arguments)}</dd>
              </div>
              <div :if={@prepared.arguments[:amount_atomic]}>
                <dt>Amount</dt><dd>80 USDC</dd>
              </div>
              <div>
                <dt>Network</dt><dd>Base</dd>
              </div>
              <div>
                <dt>Wallet</dt>
                <dd>
                  <span class="redeem-mono">{short(@prepared.expected_signer)}</span>
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
                <dt>Contract</dt><dd class="redeem-mono">{short(@prepared.to)}</dd>
              </div>
              <div>
                <dt>Native value</dt><dd>0 ETH</dd>
              </div>
            </dl>
            <p :if={!signable?(@prepared, @wallet)} role="status">
              This review belongs to another wallet. Switch back to it to finish or dismiss the
              request there.
            </p>
            <div :if={!@submission} class="redeem-button-row">
              <button
                :if={signable?(@prepared, @wallet)}
                type="button"
                data-redeem-confirm={@prepared.action_id}
                data-redeem-signer={@prepared.expected_signer}
                disabled={@signing}
              >
                {if @signing, do: "Waiting for wallet", else: "Confirm in wallet"}
              </button>
              <button type="button" phx-click="cancel_redemption_review">Cancel review</button>
            </div>
          </section>
        </section>
      </div>
    </section>
    """
  end

  # The domain decides the next step; this only says it. Claim is independent of
  # the ladder and stays a separate control.
  defp step_label(:token_selection_required),
    do: "Choose a collection and a token ID between 1 and 999."

  defp step_label(:nft_owner_unavailable), do: @unavailable_owner
  defp step_label(:nft_not_owned), do: "This wallet does not own the selected Animata token."

  defp step_label(:nft_approval_required),
    do: "Approve the selected collection for the Animata redeemer."

  defp step_label(:exact_usdc_approval_required),
    do: "Approve exactly 80 USDC for the Animata redeemer."

  defp step_label(:insufficient_usdc), do: "This wallet needs at least 80 USDC."

  defp step_label(:ready),
    do: "Redeem this Animata for a Regents Club token and the REGENT stream."

  defp step_label(_unavailable), do: "Redemption details are unavailable."

  defp step_action(:nft_approval_required), do: "approve_nft_collection"
  defp step_action(:exact_usdc_approval_required), do: "approve_exact_usdc"
  defp step_action(:ready), do: "redeem"
  defp step_action(_blocked), do: nil

  defp step_control(:nft_approval_required), do: "Review collection approval"
  defp step_control(:exact_usdc_approval_required), do: "Review USDC approval"
  defp step_control(_other), do: "Review redemption"

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="redeem-metric">
      <p class="redeem-metric-label">{@label}</p>
      <p class="redeem-metric-value">{@value}</p>
    </div>
    """
  end

  attr :hash, :string, required: true

  defp transaction(assigns) do
    assigns = assign(assigns, :url, explorer_url(assigns.hash))

    ~H"""
    <a :if={@url} class="redeem-mono" href={@url} target="_blank" rel="noopener">
      {short_hash(@hash)}
    </a>
    """
  end

  attr :notice, :map, required: true

  defp notice(assigns) do
    ~H"""
    <p class="redeem-notice" role={if @notice.tone == :error, do: "alert", else: "status"}>
      {@notice.message}
    </p>
    """
  end

  defp usdc(nil), do: "—"
  defp usdc(value), do: value <> " USDC"
  defp regent(nil), do: "—"
  defp regent(value), do: value <> " REGENT"

  # The exact result this transaction's own event recorded, which no later
  # balance can replace.
  defp confirmed_result(%{status: :confirmed, event: %{result_token_id: token_id}}),
    do: "Redeemed for Regents Club token ##{token_id}."

  defp confirmed_result(%{status: :confirmed, event: %{claimed: amount}}),
    do: "Claimed #{amount} REGENT."

  defp confirmed_result(_submission), do: nil

  defp locked?(_prepared, %{status: status}) when status not in [:confirmed, :unverified],
    do: true

  defp locked?(prepared, _submission), do: not is_nil(prepared)

  # Only the wallet a review was prepared for may open that wallet, so a review
  # left by another wallet stays visible for recovery without a signing control.
  defp signable?(%{expected_signer: signer}, wallet), do: signer == wallet

  defp claim_ready?(redemption), do: parse_integer(redemption.claimable_raw) > 0
  defp valid_token_input?(value), do: parse_integer(value) in 1..999

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> -1
    end
  end

  defp parse_integer(_value), do: -1

  defp action_label("approve_nft_collection"), do: "Approve NFT collection"
  defp action_label("approve_exact_usdc"), do: "Approve exactly 80 USDC"
  defp action_label("redeem"), do: "Redeem Animata"
  defp action_label("claim"), do: "Claim unlocked REGENT"

  defp selection(arguments) do
    collection = collection_label_from_address(arguments[:collection])

    if arguments[:token_id],
      do: "#{collection} · Token ##{arguments[:token_id]}",
      else: "#{collection} collection"
  end

  defp collection_label("animata_i"), do: "Animata I"
  defp collection_label("animata_ii"), do: "Animata II"

  defp collection_label_from_address("0x78402119ec6349a0d41f12b54938de7bf783c923"),
    do: "Animata I"

  defp collection_label_from_address("0x903c4c1e8b8532fbd3575482d942d493eb9266e2"),
    do: "Animata II"

  defp short("0x" <> address),
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short_hash("0x" <> hash) when byte_size(hash) == 64,
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"

  # Only the one canonical hash shape becomes a link to the Base explorer.
  defp explorer_url(hash) do
    if String.match?(hash, ~r/\A0x[0-9a-fA-F]{64}\z/), do: "https://basescan.org/tx/" <> hash
  end
end
