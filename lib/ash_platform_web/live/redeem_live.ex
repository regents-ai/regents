defmodule AshPlatformWeb.RedeemLive do
  @moduledoc false
  use Phoenix.Component
  alias AshPlatformWeb.TokenDisplay

  @unavailable_owner "Unable to verify this NFT. Check the collection and token ID."
  def unavailable_owner_copy, do: @unavailable_owner

  attr :redemption, :map, default: nil
  attr :status, :atom, required: true
  attr :wallet, :string, default: nil
  attr :collection, :string, required: true
  attr :token_id, :string, required: true
  attr :notice, :map, default: nil
  attr :reading, :boolean, default: false
  attr :refresh_block, :any, default: nil
  attr :step, :atom, default: nil
  attr :owned_collectibles, :map, default: %{status: :idle, animata: [], regents_club: []}
  attr :owned_collectibles_limit, :integer, default: 24

  def redemption_page(assigns) do
    assigns =
      assigns
      |> assign(:wallet_ready, wallet_ready?(assigns.redemption, assigns.wallet))
      |> assign(:vest_progress, vest_progress(assigns.redemption))
      |> assign_owned_collectibles()

    ~H"""
    <section
      id="animata-redemption"
      phx-hook="RedemptionWallet"
      class="redeem-page"
      aria-busy={to_string(@reading)}
    >
      <section id="redeem-intro" class="redeem-intro" aria-labelledby="redemption-page-heading">
        <div class="redeem-intro-copy">
          <p class="redeem-kicker">Animata redemption · Base</p>
          <h1 id="redemption-page-heading" tabindex="-1">Redeem your Animata.</h1>
          <p class="redeem-lede">
            Turn an eligible Animata I or II into Regents Club membership and a seven-day REGENT vest. Review the full exchange before connecting.
          </p>
          <div
            class="redeem-equation"
            aria-label="One Animata plus 80 USDC becomes one Regents Club membership and five million REGENT vested over seven days"
          >
            <span>1 Animata</span><b>+</b><span>80 USDC</span><b>→</b><span>Regents Club</span><b>+</b><span>5M REGENT</span>
          </div>
          <div class="redeem-intro-actions">
            <button :if={!@wallet} type="button" class="redeem-primary" data-redeem-connect>Connect wallet to redeem</button>
            <a href="#redemption-collections">Review collections</a>
          </div>
          <p class="redeem-auth-note">
            No Regent account or Privy login is required. Every Base transaction is confirmed in your wallet.
          </p>
        </div>

        <figure id="redeem-intro-media" class="redeem-intro-media">
          <video
            class="redeem-intro-video"
            autoplay
            muted
            loop
            playsinline
            preload="metadata"
            poster="/images/redeem/animata1and2-poster.jpg"
            aria-hidden="true"
            tabindex="-1"
          >
            <source
              src="/images/redeem/animata1and2.mp4"
              type="video/mp4"
              media="(prefers-reduced-motion: no-preference)"
            />
          </video>
          <img
            class="redeem-intro-poster"
            src="/images/redeem/animata1and2-poster.jpg"
            alt="Animata I and II artwork"
          />
          <figcaption><span>5,000,000 REGENT</span><span>7-day linear vest</span></figcaption>
        </figure>
      </section>

      <div
        id="redemption-transaction-progress"
        class="redeem-transaction-progress"
        data-redemption-progress
        data-phase="idle"
        role="status"
        aria-live="polite"
        aria-atomic="true"
        phx-update="ignore"
        hidden
      >
        <span class="redeem-progress-mark" aria-hidden="true"></span>
        <div>
          <strong data-redemption-progress-title></strong><p data-redemption-progress-copy></p>
        </div>
      </div>

      <dialog
        id="redemption-result-dialog"
        class="redeem-result-dialog"
        aria-labelledby="redemption-result-heading"
        phx-update="ignore"
      >
        <p class="redeem-dialog-kicker">Base transaction receipt</p>
        <h2 id="redemption-result-heading" data-redemption-result-title>Transaction update</h2>
        <p class="redeem-dialog-summary" data-redemption-result-text></p>
        <p class="redeem-dialog-detail" data-redemption-result-detail></p>
        <dl class="redeem-dialog-meta">
          <div>
            <dt>Network</dt><dd>Base</dd>
          </div>
          <div>
            <dt>Wallet</dt><dd data-redemption-result-wallet>—</dd>
          </div>
        </dl>
        <a data-redemption-result-link hidden target="_blank" rel="noopener noreferrer"></a>
        <form method="dialog"><button type="submit" value="close">Done</button></form>
      </dialog>

      <div :if={@status == :loading} class="redeem-status" aria-busy="true">
        Loading redemption contract data…
      </div>
      <div :if={@status == :error} class="redeem-status">
        <p role="alert">Redemption details are unavailable right now.</p>
        <button
          id="redemption-refresh"
          type="button"
          phx-click="refresh_redemption"
          disabled={@reading}
        >Try again</button>
      </div>

      <div :if={@status == :ready && @redemption} class="redeem-content">
        <section
          id="redemption-collections"
          class="redeem-collections"
          aria-labelledby="redemption-collections-heading"
        >
          <div class="redeem-section-heading">
            <div>
              <p class="redeem-kicker">Three connected collections</p><h2 id="redemption-collections-heading">
                What goes in. What comes out.
              </h2>
            </div>
            <p>Eligible source token IDs are 1–{@redemption.max_source_token_id}.</p>
          </div>
          <div class="redeem-collection-grid">
            <.collection_card
              kind="source"
              index="I"
              title="Animata I"
              count={@redemption.animata_i_held_by_redeemer}
              count_label="held by redeemer"
              href="https://opensea.io/collection/animata"
            />
            <.collection_card
              kind="source"
              index="II"
              title="Animata II"
              count={@redemption.animata_ii_held_by_redeemer}
              count_label="held by redeemer"
              href="https://opensea.io/collection/regent-animata-ii"
            />
            <.collection_card
              kind="result"
              index="RC"
              title="Regents Club"
              count={@redemption.regents_club_ready}
              count_label="memberships ready"
              href="https://opensea.io/collection/regents-club"
            />
          </div>
        </section>

        <p
          id="redemption-refresh-status"
          class="redeem-refresh-status"
          data-visible={to_string(not is_nil(@refresh_block))}
          role="status"
          aria-live="polite"
          aria-atomic="true"
          aria-hidden={to_string(is_nil(@refresh_block))}
        >
          <span :if={@refresh_block}>Refresh complete. Data is current at Base safe block {format_block_number(
            @refresh_block
          )}.</span>
        </p>

        <div class="redeem-layout">
          <section class="redeem-actions" aria-labelledby="redemption-actions-heading">
            <div class="redeem-section-heading">
              <div>
                <p class="redeem-kicker">Redemption flow</p><h2 id="redemption-actions-heading">
                  {if @wallet, do: "Complete your redemption", else: "Redeem in four signed steps"}
                </h2>
              </div>
              <span :if={@wallet} class="redeem-signer" title={@wallet}><span aria-hidden="true"></span>{short_wallet(
                @wallet
              )}</span>
            </div>

            <div :if={!@wallet} class="redeem-connect-panel">
              <p>
                Connect the wallet that owns your Animata. Privy provides the wallet connection; it does not sign in to Regent.
              </p>
              <button type="button" class="redeem-primary" data-redeem-connect>Connect wallet</button>
              <ul>
                <li>The page checks ownership and allowances on Base.</li>
                <li>Approvals are requested only when the contract needs them.</li>
                <li>Your wallet confirms every transaction separately.</li>
              </ul>
            </div>

            <.notice :if={@wallet && @notice} notice={@notice} />

            <div
              :if={@wallet && !@wallet_ready && @reading}
              class="redeem-wallet-loading"
              role="status"
            >
              <span class="redeem-progress-mark" aria-hidden="true"></span>
              <p>
                Loading this wallet’s collection and vest while public collection data stays visible…
              </p>
            </div>

            <div :if={@wallet && !@wallet_ready && !@reading} class="redeem-wallet-recovery">
              <p>
                Your wallet is connected, but its latest Base redemption data could not be loaded.
              </p>
              <div>
                <button type="button" phx-click="refresh_redemption">Try again</button>
                <button type="button" data-redeem-connect>Switch wallet</button>
              </div>
            </div>

            <div :if={@wallet_ready} class="redeem-wallet-flow">
              <ol class="redeem-stepper" aria-label="Redemption progress">
                <.flow_step number="1" label="Select Animata" state={flow_state(1, @step)} />
                <.flow_step number="2" label="Approve NFT" state={flow_state(2, @step)} />
                <.flow_step number="3" label="Approve 80 USDC" state={flow_state(3, @step)} />
                <.flow_step number="4" label="Redeem" state={flow_state(4, @step)} />
              </ol>

              <form id="redemption-selection" phx-change="redemption_selection_changed">
                <div>
                  <label for="redemption-collection">Collection</label>
                  <select id="redemption-collection" name="collection">
                    <option value="animata_i" selected={@collection == "animata_i"}>Animata I</option>
                    <option value="animata_ii" selected={@collection == "animata_ii"}>
                      Animata II
                    </option>
                  </select>
                </div>
                <div>
                  <label for="redemption-token-id">Token ID</label>
                  <input
                    id="redemption-token-id"
                    name="token_id"
                    value={@token_id}
                    inputmode="numeric"
                    autocomplete="off"
                    placeholder="1–999"
                  />
                </div>
              </form>

              <section class="redeem-next-step" aria-label="Next step" data-step={@step}>
                <div>
                  <p class="redeem-kicker">Next required action</p><h3>{step_control(@step)}</h3><p>
                    {step_label(@step)}
                  </p>
                </div>
                <button
                  type="button"
                  class="redeem-primary"
                  data-redemption-action={step_action(@step)}
                  disabled={is_nil(step_action(@step))}
                >{step_control(@step)}</button>
              </section>

              <div class="redeem-wallet-footer">
                <button
                  id="redemption-refresh"
                  type="button"
                  phx-click="refresh_redemption"
                  disabled={@reading}
                  aria-describedby={if(@refresh_block, do: "redemption-refresh-status")}
                >
                  {if @reading, do: "Updating…", else: "Refresh wallet data"}
                </button>
                <button type="button" data-redeem-connect>Switch wallet</button>
              </div>
            </div>
          </section>

          <section
            :if={@wallet_ready}
            class="redeem-position"
            aria-labelledby="redemption-position-heading"
          >
            <div class="redeem-section-heading">
              <div>
                <p class="redeem-kicker">Your account</p><h2 id="redemption-position-heading">
                  Redemption and vest
                </h2>
              </div>
              <span class="redeem-network">Base</span>
            </div>
            <section class="redeem-summary" aria-label="Redemption account status">
              <.metric label="USDC balance">
                <TokenDisplay.amount amount={@redemption.usdc_balance} unit="USDC" />
              </.metric>
              <.metric label="Current allowance">
                <TokenDisplay.amount amount={@redemption.usdc_allowance} unit="USDC" />
              </.metric>
              <.metric label="Claimable now">
                <TokenDisplay.amount amount={@redemption.claimable} unit="REGENT" />
              </.metric>
              <.metric label="Vesting total">
                <TokenDisplay.amount amount={@redemption.vest_pool} unit="REGENT" />
              </.metric>
            </section>

            <div class="redeem-vest">
              <div class="redeem-vest-heading">
                <span>Vesting released</span><strong>{@vest_progress.label}</strong>
              </div>
              <progress max="100" value={@vest_progress.value} aria-label="REGENT vesting released">{@vest_progress.label}</progress>
              <dl>
                <div>
                  <dt>Released</dt><dd>
                    <TokenDisplay.amount amount={@redemption.vest_released} unit="REGENT" />
                  </dd>
                </div>
                <div>
                  <dt>Claimed</dt><dd>
                    <TokenDisplay.amount amount={@redemption.vest_claimed} unit="REGENT" />
                  </dd>
                </div>
              </dl>
            </div>

            <button
              type="button"
              class="redeem-claim"
              data-redemption-action="claim"
              disabled={!claim_ready?(@redemption)}
            >Claim unlocked REGENT</button>
            <p class="redeem-snapshot-note">
              <span>Confirmed at Base safe block {format_block_number(@redemption.block_number)}.</span><span :if={
                @reading
              }> Updating from Base…</span>
            </p>
          </section>
        </div>

        <section :if={@wallet} class="redeem-owned" aria-labelledby="redemption-owned-heading">
          <div class="redeem-section-heading">
            <div>
              <p class="redeem-kicker">Connected collection</p><h2 id="redemption-owned-heading">
                Your supported NFTs
              </h2>
            </div>
            <p>Select an Animata card to fill the redemption form.</p>
          </div>
          <p :if={@owned_collectibles.status == :loading} class="redeem-owned-status">
            Checking Animata and Regents Club…
          </p>
          <p :if={@owned_collectibles.status == :refreshing} class="redeem-owned-status">
            Updating your collection from OpenSea…
          </p>
          <p :if={@owned_collectibles.status == :unavailable} class="redeem-owned-status">
            Owned NFT lookup is unavailable. Enter a collection and token ID manually.
          </p>
          <p :if={@owned_collectibles.status == :empty} class="redeem-owned-status">
            No supported NFTs were found. Manual selection remains available.
          </p>
          <div class="redeem-owned-list">
            <button
              :for={{item, index} <- Enum.with_index(@visible_animata)}
              type="button"
              class="redeem-nft-card"
              data-collection={item.collection}
              style={"--card-index: #{min(index, 12)}"}
              phx-click="select_owned_animata"
              phx-value-collection={item.collection}
              phx-value-token-id={item.token_id}
            >
              <span class="redeem-nft-art" aria-hidden="true"></span><span class="redeem-nft-type">{if item.collection ==
                                                                                                         "animata_i",
                                                                                                       do:
                                                                                                         "Animata I",
                                                                                                       else:
                                                                                                         "Animata II"}</span><strong>#{item.token_id}</strong><span class="redeem-nft-action">Select to redeem →</span>
            </button>
            <a
              :for={{item, index} <- Enum.with_index(@visible_regents_club)}
              class="redeem-nft-card redeem-nft-card-club"
              style={"--card-index: #{min(index + length(@visible_animata), 12)}"}
              href={item.href}
              target="_blank"
              rel="noopener noreferrer"
            >
              <span class="redeem-nft-art" aria-hidden="true"></span><span class="redeem-nft-type">Regents Club</span><strong>#{item.token_id}</strong><span class="redeem-nft-action">View on OpenSea ↗</span>
            </a>
          </div>
          <button
            :if={@owned_collectibles_limit < @owned_collectibles_total}
            type="button"
            class="redeem-owned-more"
            phx-click="show_more_collectibles"
          >Show more ({@owned_collectibles_total - @owned_collectibles_limit} remaining)</button>
        </section>

        <details class="redeem-contract-details">
          <summary>
            <span><span class="redeem-kicker">Verification</span> Redemption contract details</span><span aria-hidden="true">+</span>
          </summary>
          <dl>
            <div>
              <dt>Redeemer</dt><dd><code>{@redemption.redeemer_address}</code></dd>
            </div>
            <div>
              <dt>Animata I</dt><dd><code>{@redemption.animata_i_address}</code></dd>
            </div>
            <div>
              <dt>Animata II</dt><dd><code>{@redemption.animata_ii_address}</code></dd>
            </div>
            <div>
              <dt>Regents Club</dt><dd><code>{@redemption.result_collection_address}</code></dd>
            </div>
            <div>
              <dt>Safe Base block</dt><dd>
                <span>{format_block_number(@redemption.block_number)}</span><code>{@redemption.block_hash}</code>
              </dd>
            </div>
          </dl>
        </details>
      </div>
    </section>
    """
  end

  defp assign_owned_collectibles(assigns) do
    visible_animata =
      Enum.take(assigns.owned_collectibles.animata, assigns.owned_collectibles_limit)

    club_limit = max(assigns.owned_collectibles_limit - length(visible_animata), 0)

    assigns
    |> assign(:visible_animata, visible_animata)
    |> assign(
      :visible_regents_club,
      Enum.take(assigns.owned_collectibles.regents_club, club_limit)
    )
    |> assign(
      :owned_collectibles_total,
      length(assigns.owned_collectibles.animata) + length(assigns.owned_collectibles.regents_club)
    )
  end

  defp step_label(:token_selection_required),
    do: "Choose an eligible Animata collection and token ID."

  defp step_label(:nft_owner_unavailable), do: @unavailable_owner
  defp step_label(:nft_not_owned), do: "This wallet does not own the selected Animata token."

  defp step_label(:nft_approval_required),
    do: "Allow the redeemer to transfer from this NFT collection."

  defp step_label(:exact_usdc_approval_required),
    do: "Set the redeemer’s allowance to exactly 80 USDC."

  defp step_label(:insufficient_usdc),
    do: "This wallet needs at least 80 USDC before it can redeem."

  defp step_label(:ready), do: "Exchange the selected Animata and 80 USDC on Base."
  defp step_label(_), do: "Choose an Animata to see the required action."

  defp step_action(:nft_approval_required), do: "approve_nft_collection"
  defp step_action(:exact_usdc_approval_required), do: "approve_exact_usdc"
  defp step_action(:ready), do: "redeem"
  defp step_action(_), do: nil

  defp step_control(:token_selection_required), do: "Select an Animata"
  defp step_control(:nft_approval_required), do: "Approve NFT collection"
  defp step_control(:exact_usdc_approval_required), do: "Approve 80 USDC"
  defp step_control(:insufficient_usdc), do: "80 USDC required"
  defp step_control(:ready), do: "Redeem Animata"
  defp step_control(_), do: "Action unavailable"

  defp flow_state(1, :token_selection_required), do: "current"
  defp flow_state(1, nil), do: "current"
  defp flow_state(1, _), do: "complete"
  defp flow_state(2, :nft_approval_required), do: "current"

  defp flow_state(2, step)
       when step in [:exact_usdc_approval_required, :insufficient_usdc, :ready], do: "complete"

  defp flow_state(2, _), do: "upcoming"
  defp flow_state(3, :exact_usdc_approval_required), do: "current"
  defp flow_state(3, step) when step in [:insufficient_usdc, :ready], do: "complete"
  defp flow_state(3, _), do: "upcoming"
  defp flow_state(4, :ready), do: "current"
  defp flow_state(4, _), do: "upcoming"

  defp wallet_ready?(redemption, wallet) when is_map(redemption) and is_binary(wallet),
    do: Map.get(redemption, :wallet_address) == wallet

  defp wallet_ready?(_, _), do: false

  defp claim_ready?(redemption) do
    case Integer.parse(redemption.claimable_raw || "") do
      {value, ""} -> value > 0
      _ -> false
    end
  end

  defp vest_progress(nil), do: %{label: "0%", value: "0"}

  defp vest_progress(redemption) do
    with {released, ""} <- Integer.parse(redemption.vest_released_raw || ""),
         {pool, ""} <- Integer.parse(redemption.vest_pool_raw || ""),
         true <- pool > 0 do
      percentage =
        released
        |> Decimal.new()
        |> Decimal.mult(100)
        |> Decimal.div(Decimal.new(pool))
        |> Decimal.min(Decimal.new(100))
        |> Decimal.round(2)
        |> Decimal.normalize()
        |> Decimal.to_string(:normal)

      %{label: "#{percentage}%", value: percentage}
    else
      _ -> %{label: "0%", value: "0"}
    end
  end

  defp short_wallet("0x" <> address) when byte_size(address) == 40,
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short_wallet(wallet), do: wallet

  defp format_block_number(block_number) do
    block_number
    |> to_string()
    |> String.reverse()
    |> String.replace(~r/(.{3})(?=.)/, "\\1,")
    |> String.reverse()
  end

  attr :kind, :string, required: true
  attr :index, :string, required: true
  attr :title, :string, required: true
  attr :count, :integer, required: true
  attr :count_label, :string, required: true
  attr :href, :string, required: true

  defp collection_card(assigns) do
    ~H"""
    <article class="redeem-collection-card" data-kind={@kind}>
      <div class="redeem-collection-art" aria-hidden="true"><span>{@index}</span></div>
      <div class="redeem-collection-copy">
        <p>{if @kind == "source", do: "Redemption source", else: "Membership result"}</p>
        <h3>{@title}</h3>
        <dl>
          <div>
            <dt>Live contract count</dt><dd>{format_block_number(@count)} {@count_label}</dd>
          </div><div>
            <dt>{if @kind == "source", do: "Eligible IDs", else: "Received on redeem"}</dt><dd>
              {if @kind == "source", do: "1–999", else: "1 membership NFT"}
            </dd>
          </div>
        </dl>
        <a href={@href} target="_blank" rel="noopener noreferrer">View collection on OpenSea ↗</a>
      </div>
    </article>
    """
  end

  attr :number, :string, required: true
  attr :label, :string, required: true
  attr :state, :string, required: true

  defp flow_step(assigns) do
    ~H"""
    <li data-state={@state}>
      <span>{if @state == "complete", do: "✓", else: @number}</span><p>{@label}</p>
    </li>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp metric(assigns) do
    ~H"""
    <div class="redeem-metric">
      <p class="redeem-metric-label">{@label}</p><p class="redeem-metric-value">
        {render_slot(@inner_block)}
      </p>
    </div>
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
end
