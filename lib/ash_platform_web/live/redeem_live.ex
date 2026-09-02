defmodule AshPlatformWeb.RedeemLive do
  @moduledoc false
  use Phoenix.Component
  alias AshPlatformWeb.Components.Shell
  alias AshPlatformWeb.TokenDisplay

  @control_labels %{
    "approve_nft_collection" => "Approve NFT collection",
    "approve_exact_usdc" => "Approve 80 USDC",
    "redeem" => "Redeem Animata"
  }
  @every_control ~w(approve_nft_collection approve_exact_usdc redeem)

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
  attr :actions, :atom, default: :sign_in, values: [:ready, :sign_in, :mismatch]

  def redemption_page(assigns) do
    assigns =
      assigns
      |> assign(:wallet_ready, wallet_ready?(assigns.redemption, assigns.wallet))
      |> assign(:vest_progress, vest_progress(assigns.redemption))
      |> assign(:token_selected, token_selected?(assigns.token_id))
      |> assign_owned_collectibles()

    assigns = assign(assigns, :controls, controls(assigns.step, assigns.token_selected))

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
            Turn an eligible Animata I or II into Regents Club membership and a seven-day REGENT vest.
          </p>
          <div
            class="redeem-equation"
            aria-label="One Animata plus 80 USDC becomes five million REGENT vested over seven days and one Regents Club membership"
          >
            <span class="redeem-pill">1 Animata</span><b>+</b><span class="redeem-pill">80 USDC</span><b>→</b><span class="redeem-equation-result"><span class="redeem-pill">5 million REGENT</span><b>+</b><span class="redeem-pill">Regents Club</span></span>
          </div>
          <div :if={!@wallet} class="redeem-intro-actions">
            <button type="button" class="redeem-primary" data-account-target="sign-in">
              Connect wallet to redeem
            </button>
          </div>
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
        </figure>
      </section>

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
        >Refresh Data</button>
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
                Animata I+II + USDC are redeemed for REGENT + RC NFT
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
          <span :if={@refresh_block}>Refresh complete. Data is current at Base block {TokenDisplay.count(
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
              <span :if={@wallet} class="redeem-signer" title={@wallet}><span aria-hidden="true"></span>{Shell.short_wallet(
                @wallet
              )}</span>
            </div>

            <div :if={!@wallet} class="redeem-connect-panel">
              <p>
                Sign in with Privy and connect the wallet that owns your Animata.
              </p>
              <button type="button" class="redeem-primary" data-account-target="sign-in">
                Connect wallet
              </button>
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
                    phx-debounce="300"
                    inputmode="numeric"
                    autocomplete="off"
                    placeholder="1–999"
                  />
                </div>
              </form>

              <section class="redeem-next-step" aria-label="Next step" data-step={@step}>
                <div>
                  <p class="redeem-kicker">Next required action</p><h3>
                    {step_heading(
                      @step,
                      @token_selected
                    )}
                  </h3><p id="redemption-step-hint">{step_label(@step, @token_selected)}</p>
                </div>
                <div :if={@controls != []}>
                  <button
                    :for={control <- @controls}
                    type="button"
                    class="redeem-primary"
                    data-redemption-action={@actions != :sign_in && control.action}
                    data-account-target={@actions == :sign_in && "sign-in"}
                    aria-describedby="redemption-step-hint"
                  >{control.label}</button>
                </div>
              </section>

              <div class="redeem-wallet-footer">
                <button
                  id="redemption-refresh"
                  type="button"
                  phx-click="refresh_redemption"
                  disabled={@reading}
                  aria-describedby={if(@refresh_block, do: "redemption-refresh-status")}
                >
                  {if @reading, do: "Updating…", else: "Refresh Data"}
                </button>
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
              data-redemption-action={@actions != :sign_in && "claim"}
              data-account-target={@actions == :sign_in && "sign-in"}
            >
              Claim unlocked REGENT
            </button>
            <p class="redeem-snapshot-note">
              <span>Confirmed at Base block {TokenDisplay.count(@redemption.block_number)}.</span><span :if={
                @reading
              }> Updating from Base…</span>
            </p>
          </section>
        </div>

        <section :if={@wallet} class="redeem-owned" aria-labelledby="redemption-owned-heading">
          <div class="redeem-section-heading">
            <div>
              <p class="redeem-kicker">Connected collection</p><h2 id="redemption-owned-heading">
                Owned Collectibles
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
              <dt>Base block</dt><dd>
                <span>{TokenDisplay.count(@redemption.block_number)}</span><code>{@redemption.block_hash}</code>
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

  # A control is offered whenever its calldata can be built, which needs only a
  # connected wallet and a selected token. When the last reading from Base names
  # the step, that one control is offered; when it does not, all three are, and
  # the hint says why. Nothing here withholds a send.
  defp controls(_step, false), do: []

  defp controls(step, true) do
    for action <- step_controls(step), do: %{action: action, label: @control_labels[action]}
  end

  defp step_controls(:nft_approval_required), do: ["approve_nft_collection"]
  defp step_controls(:exact_usdc_approval_required), do: ["approve_exact_usdc"]

  defp step_controls(step) when step in [:ready, :nft_not_owned, :insufficient_usdc],
    do: ["redeem"]

  defp step_controls(_unknown), do: @every_control

  defp step_heading(_step, false), do: "Select an Animata"

  defp step_heading(step, true) do
    case step_controls(step) do
      [action] -> @control_labels[action]
      _every -> "Approve or redeem"
    end
  end

  defp step_label(_step, false), do: "Choose an eligible Animata collection and token ID."

  defp step_label(:nft_approval_required, true),
    do: "Allow the redeemer to transfer from this NFT collection."

  defp step_label(:exact_usdc_approval_required, true),
    do: "Set the redeemer’s allowance to exactly 80 USDC."

  defp step_label(:ready, true), do: "Exchange the selected Animata and 80 USDC on Base."

  defp step_label(:nft_not_owned, true),
    do: "This wallet does not own the selected Animata in the last reading from Base."

  defp step_label(:insufficient_usdc, true),
    do: "This wallet holds less than 80 USDC in the last reading from Base."

  defp step_label(:nft_owner_unavailable, true),
    do:
      "The owner of the selected Animata could not be read in the last reading from Base, so any of these steps can be sent."

  defp step_label(:chain_unavailable, true),
    do: "The last reading from Base is unavailable, so any of these steps can be sent."

  defp step_label(_step, true),
    do:
      "The last reading from Base does not yet say which step is needed, so any of these steps can be sent."

  defp token_selected?(token_id) when is_binary(token_id) do
    case Integer.parse(token_id) do
      {id, ""} -> id in 1..999
      _ -> false
    end
  end

  defp token_selected?(_token_id), do: false

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
            <dt>Live contract count</dt><dd>{TokenDisplay.count(@count)} {@count_label}</dd>
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
