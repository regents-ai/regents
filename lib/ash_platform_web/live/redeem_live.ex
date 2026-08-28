defmodule AshPlatformWeb.RedeemLive do
  @moduledoc false
  use Phoenix.Component
  alias AshPlatformWeb.TokenDisplay
  @unavailable_owner "Unable to verify this NFT. Check the collection and token ID."
  def unavailable_owner_copy, do: @unavailable_owner

  attr :redemption, :map, default: nil
  attr :status, :atom, required: true
  attr :authenticated, :boolean, required: true
  attr :wallet, :string, default: nil
  attr :collection, :string, required: true
  attr :token_id, :string, required: true
  attr :notice, :map, default: nil
  attr :reading, :boolean, default: false
  attr :step, :atom, default: nil
  attr :owned_collectibles, :map, default: %{status: :idle, animata: [], regents_club: []}

  def redemption_page(assigns) do
    ~H"""
    <section id="animata-redemption" phx-hook="RedemptionWallet" class="redeem-page">
      <section id="redeem-intro" class="redeem-intro" aria-labelledby="redeem-intro-title">
        <figure
          id="redeem-intro-media"
          class="redeem-intro-media"
          role="img"
          aria-label="Animata Collection I and II artwork"
        >
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
            alt=""
            aria-hidden="true"
          />
        </figure>
        <div class="redeem-intro-copy">
          <h1 id="redeem-intro-title">See Animata Collection I and II on OpenSea</h1>
          <nav class="redeem-intro-links" aria-label="Animata OpenSea collections">
            <a
              href="https://opensea.io/collection/animata"
              target="_blank"
              rel="noopener noreferrer"
            >Animata I</a><a
              href="https://opensea.io/collection/regent-animata-ii"
              target="_blank"
              rel="noopener noreferrer"
            >Animata II</a>
          </nav>
          <p>
            Animata I and II NFTs can be redeemed, along with 80 USDC, for 5,000,000 REGENT. You will also receive a membership NFT in the Regents Club, <a
              href="https://opensea.io/collection/regents-club"
              target="_blank"
              rel="noopener noreferrer"
            >seen here</a>.
          </p>
        </div>
      </section>
      <header class="redeem-heading">
        <p class="redeem-kicker">Regents Labs · Base</p><h2>Redeem Animata</h2>
        <p>
          Redeem an Animata I or II token for a Regents Club token and a seven-day stream of 5,000,000 REGENT.
        </p>
      </header>
      <section class="redeem-facts" aria-label="Redemption facts">
        <.metric label="Cost">80 USDC</.metric><.metric label="Reward">5,000,000 REGENT</.metric><.metric label="Vesting">
          7 days
        </.metric><.metric label="Network">Base</.metric>
      </section>
      <div :if={@status == :loading} class="redeem-status" aria-busy="true">
        Loading redemption details…
      </div>
      <div :if={@status == :error} class="redeem-status">
        <p role="alert">Redemption details are unavailable right now.</p><button
          id="redemption-refresh"
          type="button"
          phx-click="refresh_redemption"
          disabled={@reading}
        >Try again</button>
      </div>

      <div :if={@status == :ready && @redemption} class="redeem-layout">
        <p
          id="redemption-refresh-status"
          class="redeem-refresh-status"
          role="status"
          aria-live="polite"
          aria-atomic="true"
        >
          Refresh complete. Data is current at Base safe block {format_block_number(
            @redemption.block_number
          )}.
        </p>
        <section class="redeem-summary" aria-label="Redemption account status">
          <.metric label="USDC balance">
            <TokenDisplay.amount amount={@redemption.usdc_balance} unit="USDC" />
          </.metric>
          <.metric label="USDC allowance">
            <TokenDisplay.amount amount={@redemption.usdc_allowance} unit="USDC" />
          </.metric>
          <.metric label="Claimable REGENT">
            <TokenDisplay.amount amount={@redemption.claimable} unit="REGENT" />
          </.metric>
          <.metric label="Vest total">
            <TokenDisplay.amount amount={@redemption.vest_pool} unit="REGENT" />
          </.metric>
          <.metric label="Released">
            <TokenDisplay.amount amount={@redemption.vest_released} unit="REGENT" />
          </.metric>
          <.metric label="Claimed">
            <TokenDisplay.amount amount={@redemption.vest_claimed} unit="REGENT" />
          </.metric>
          <.metric label="Base safe block">{format_block_number(@redemption.block_number)}</.metric>
        </section>
        <section :if={!@authenticated} class="redeem-actions">
          <h2>Connect your account</h2><button type="button" data-account-target="sign-in">Sign in to redeem</button>
        </section>
        <section :if={@authenticated && !@wallet} class="redeem-actions">
          <h2>Choose your wallet</h2><.notice :if={@notice} notice={@notice} /><button
            type="button"
            data-redeem-connect
          >Connect or switch wallet</button>
        </section>
        <section
          :if={@authenticated && @wallet}
          class="redeem-actions"
          aria-label="Redemption actions"
        >
          <.notice :if={@notice} notice={@notice} />
          <form id="redemption-selection" phx-change="redemption_selection_changed">
            <label for="redemption-collection">Collection</label><select
              id="redemption-collection"
              name="collection"
            ><option value="animata_i" selected={@collection == "animata_i"}>Animata I</option><option
              value="animata_ii"
              selected={@collection == "animata_ii"}
            >
              Animata II
            </option></select>
            <label for="redemption-token-id">Token ID</label><input
              id="redemption-token-id"
              name="token_id"
              value={@token_id}
              inputmode="numeric"
              autocomplete="off"
              placeholder="1–999"
            />
          </form>
          <section class="redeem-next-step" aria-label="Next step">
            <p class="redeem-kicker">Next step</p><p>{step_label(@step)}</p>
            <button
              type="button"
              phx-click="prepare_redemption"
              phx-value-action={step_action(@step)}
              disabled={is_nil(step_action(@step))}
            >{step_control(@step)}</button>
          </section>
          <div class="redeem-button-row">
            <button
              type="button"
              phx-click="prepare_redemption"
              phx-value-action="claim"
              disabled={!claim_ready?(@redemption)}
            >Claim unlocked REGENT</button>
            <button
              id="redemption-refresh"
              type="button"
              phx-click="refresh_redemption"
              disabled={@reading}
              aria-describedby="redemption-refresh-status"
            >Refresh</button>
          </div>
        </section>
        <section :if={@wallet} class="redeem-owned" aria-label="NFTs in this wallet">
          <h2>Your NFTs</h2><p :if={@owned_collectibles.status == :loading}>
            Checking Animata and Regents Club…
          </p>
          <p :if={@owned_collectibles.status == :unavailable}>
            Owned NFT lookup is unavailable. Enter a collection and token ID manually.
          </p>
          <p :if={@owned_collectibles.status == :empty}>
            No supported NFTs were found. Manual selection remains available.
          </p>
          <div class="redeem-owned-list">
            <button
              :for={item <- @owned_collectibles.animata}
              type="button"
              phx-click="select_owned_animata"
              phx-value-collection={item.collection}
              phx-value-token-id={item.token_id}
            >{item.label}</button>
            <a
              :for={item <- @owned_collectibles.regents_club}
              href={item.href}
              target="_blank"
              rel="noopener noreferrer"
            >{item.label}</a>
          </div>
        </section>
      </div>
    </section>
    """
  end

  defp step_label(:token_selection_required), do: "Choose a collection and token ID."
  defp step_label(:nft_owner_unavailable), do: @unavailable_owner
  defp step_label(:nft_not_owned), do: "This wallet does not own the selected Animata token."
  defp step_label(:nft_approval_required), do: "Approve the selected collection."
  defp step_label(:exact_usdc_approval_required), do: "Approve exactly 80 USDC."
  defp step_label(:insufficient_usdc), do: "This wallet needs at least 80 USDC."
  defp step_label(:ready), do: "Redeem this Animata."
  defp step_label(_), do: "Redemption details are unavailable."
  defp step_action(:nft_approval_required), do: "approve_nft_collection"
  defp step_action(:exact_usdc_approval_required), do: "approve_exact_usdc"
  defp step_action(:ready), do: "redeem"
  defp step_action(_), do: nil
  defp step_control(:nft_approval_required), do: "Approve NFT"
  defp step_control(:exact_usdc_approval_required), do: "Approve 80 USDC"
  defp step_control(:ready), do: "Redeem"
  defp step_control(_), do: "Nothing available"

  defp claim_ready?(redemption) do
    case Integer.parse(redemption.claimable_raw || "") do
      {value, ""} -> value > 0
      _ -> false
    end
  end

  defp format_block_number(block_number) do
    block_number
    |> to_string()
    |> String.reverse()
    |> String.replace(~r/(.{3})(?=.)/, "\\1,")
    |> String.reverse()
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
