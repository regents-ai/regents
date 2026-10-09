defmodule RegentsWeb.RedeemLive do
  @moduledoc """
  The Redeem page and its wallet buttons.

  Every wallet step is built on the server and pushed to the page before anyone
  presses; the browser sends only what the review holds and reports what the
  wallet said. `skills/onchain-buttons` has the rules and
  `RegentsWeb.OnchainSteps` the shared half.

  The shell owns the readings, the selection and every other control here; this
  component owns the presses. Only Privy's active wallet acts, and only when the
  signed-in account links it (`account`, `nil` signed out). The component tells
  the shell which wallet Privy has active, so the figures follow it, and when a
  step lands, so they are read again.
  """
  use RegentsWeb, :live_component

  alias Regents.{ChainClient, Redemption}
  alias Regents.Redemption.Steps

  alias RegentsWeb.Components.{
    Loading,
    OnchainButton,
    SubmittedTransactions,
    TransactionReceipt
  }

  alias Phoenix.LiveView.JS
  alias RegentChain.{Presses, Review}
  alias RegentsWeb.{EventInput, OnchainSteps, TokenDisplay}
  alias RegentsWeb.ShellLive.Identity

  @control_labels %{
    "approve_nft_collection" => "Approve NFT collection",
    "approve_exact_usdc" => "Approve 80 USDC",
    "redeem" => "Redeem Animata"
  }
  @every_control ~w(approve_nft_collection approve_exact_usdc redeem)
  @collections %{"animata_i" => "Animata I", "animata_ii" => "Animata II"}
  # Longer than any collection or token ID; the token ID input stops there too.
  @selection_limits %{"collection" => 16, "token_id" => 16}

  import RegentsWeb.EventInput, only: [failure_reason: 1]

  @impl true
  def mount(socket),
    do:
      {:ok,
       socket
       |> RegentsWeb.Live.Session.check_component_lease(&take_account/2)
       |> OnchainSteps.init()
       |> assign(
         active: nil,
         press_step: nil,
         selection: %{collection: "", token_id: ""},
         receipt: nil
       )}

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.delete(assigns, :account))
     |> assign(selection: %{collection: assigns.collection, token_id: assigns.token_id})
     |> take_account(assigns.account)}
  end

  # The account as the page gave it, or as it reads now before each event and
  # each background result (`RegentsWeb.Live.Session.check_component_lease/2`):
  # the wallets that may act and the review follow it.
  defp take_account(socket, account),
    do: socket |> assign(linked: Identity.linked_wallets(account)) |> sync()

  @impl true
  def handle_event("onchain_active_wallet", params, socket) do
    active = OnchainSteps.active_wallet(params)
    send(self(), {:redeem_active_wallet, active})

    socket =
      if active == socket.assigns.active, do: socket, else: assign(socket, press_note: nil)

    {:noreply, socket |> assign(active: active) |> sync()}
  end

  # A press made before the review caught up with the selection: the selection
  # is taken as the page shows it, and the reply carries the review for it.
  def handle_event("prepare_and_send", %{"form" => form, "step" => name}, socket)
      when is_binary(name) do
    case EventInput.texts(form, @selection_limits) do
      {:ok, fields} ->
        socket
        |> assign(
          selection: %{
            collection: Map.get(fields, "collection", ""),
            token_id: Map.get(fields, "token_id", "")
          }
        )
        |> sync()
        |> prepare(name)

      :error ->
        {:reply, %{}, assign(socket, press_note: EventInput.unreadable(), press_step: nil)}
    end
  end

  def handle_event("step_sent", params, socket),
    do: {:noreply, OnchainSteps.sent(socket, params)}

  def handle_event("step_failed", %{"step" => name, "reason" => reason}, socket)
      when is_binary(name) and failure_reason(reason) do
    {:noreply,
     assign(socket, press_note: failure_note(reason, name, socket.assigns), press_step: name)}
  end

  def handle_event("check_again", %{"hash" => hash}, socket) when is_binary(hash),
    do: {:noreply, OnchainSteps.check_again(socket, hash)}

  def handle_event("close_receipt", _params, socket),
    do: {:noreply, assign(socket, receipt: nil)}

  # Anything else the page sent is not in a shape this panel takes.
  def handle_event(_event, _params, socket),
    do: {:noreply, assign(socket, press_note: EventInput.unreadable(), press_step: nil)}

  # A step that landed moved this wallet's figures, so the page reads them again.
  @impl true
  def handle_async({:onchain_step, hash}, result, socket) do
    socket = OnchainSteps.checked(socket, hash, result)

    case Enum.find(socket.assigns.presses.sent, &(&1.hash == hash)) do
      %{outcome: :confirmed, name: name} = entry ->
        send(self(), {:redeem_step_landed, name})
        {:noreply, open_receipt(socket, entry)}

      _entry ->
        {:noreply, socket}
    end
  end

  # Only the latest receipt's reading is shown; an earlier one's answer is dropped.
  def handle_async(
        {:receipt_position, hash},
        result,
        %{assigns: %{receipt: %{hash: hash}}} = socket
      ),
      do: {:noreply, update(socket, :receipt, &%{&1 | position: position(result)})}

  def handle_async({:receipt_position, _hash}, _result, socket), do: {:noreply, socket}

  # A redemption or claim that landed opens its receipt, with the wallet's
  # vest read again after it.
  defp open_receipt(socket, %{name: name, hash: hash, review: review})
       when name in ~w(redeem claim) do
    signer = review.signer

    socket
    |> assign(receipt: %{hash: hash, name: name, inputs: review.inputs, position: :reading})
    |> start_async({:receipt_position, hash}, fn ->
      Redemption.account_for_wallet(signer, nil, nil)
    end)
  end

  defp open_receipt(socket, _entry), do: socket

  defp position({:ok, {:ok, facts}}),
    do: %{claimable: facts.claimable, vest_pool: facts.vest_pool}

  defp position(_failed), do: :unavailable

  defp receipt_title(%{name: "redeem", inputs: inputs}), do: "You redeemed #{animata(inputs)}"
  defp receipt_title(%{name: "claim"}), do: "You claimed your unlocked REGENT"

  defp receipt_summary(%{name: "redeem"}),
    do:
      "Base confirmed it. The Animata and 80 USDC left your wallet, and its REGENT now vests to you."

  defp receipt_summary(%{name: "claim"}),
    do: "Base confirmed it. The unlocked REGENT is in your wallet."

  # The review follows the signer and the selection. With no eligible signer
  # there is no review, and every press says why nothing was sent.
  defp sync(socket) do
    %{linked: linked, active: active, selection: selection} = socket.assigns

    review =
      case OnchainSteps.signer(linked, active) do
        nil ->
          nil

        signer ->
          Review.new(
            socket.assigns.id,
            signer,
            ChainClient.base(),
            Steps.steps(selection),
            %{"collection" => selection.collection, "token_id" => selection.token_id}
          )
      end

    OnchainSteps.put_review(socket, review)
  end

  defp prepare(%{assigns: %{review: nil}} = socket, _name), do: {:reply, %{}, socket}

  defp prepare(%{assigns: %{review: review}} = socket, name),
    do: {:reply, %{review: review, send: name}, socket}

  # A redemption with no token ID behind it says so; every other reason has the
  # shared words.
  defp failure_note("step_unknown", "redeem", %{linked: linked, active: active} = assigns)
       when is_list(linked) and is_binary(active) do
    (OnchainSteps.signer(linked, active) && Steps.token_id(assigns.selection.token_id) == :error &&
       "Enter a token ID from 1 to 999. Nothing was sent.") ||
      OnchainSteps.failure_note("step_unknown", linked, active, "Base")
  end

  defp failure_note(reason, _name, %{linked: linked, active: active}),
    do: OnchainSteps.failure_note(reason, linked, active, "Base")

  # Each sent step as the page shows it, newest first, beside the buttons that
  # send it: the redemption flow's steps, or the claim.
  defp shown(presses, names) do
    for entry <- Presses.shown(presses), entry.name in names do
      shown = OnchainSteps.describe(entry, "Base")

      %{
        hash: entry.hash,
        title: title(entry.name, entry.review.inputs),
        state: shown.state,
        words: step_words(shown.state, entry.name, entry.review.inputs) || shown.words,
        href: "https://basescan.org/tx/#{entry.hash}"
      }
    end
  end

  defp step_words(:confirmed, name, inputs), do: confirmed(name, inputs)
  defp step_words(:reverted, name, _inputs), do: reverted(name)
  defp step_words(_state, _name, _inputs), do: nil

  defp title("approve_nft_collection", inputs), do: "#{collection(inputs)} approval"
  defp title("approve_exact_usdc", _inputs), do: "80 USDC approval"
  defp title("redeem", inputs), do: "Redeem #{animata(inputs)}"
  defp title("claim", _inputs), do: "REGENT claim"

  defp confirmed("approve_nft_collection", inputs),
    do: "Done. #{collection(inputs)} is approved for redemption."

  defp confirmed("approve_exact_usdc", _inputs),
    do: "Done. Exactly 80 USDC is approved for redemption."

  defp confirmed("redeem", inputs),
    do: "Done. #{animata(inputs)} was redeemed. Your collection and vest are updating."

  defp confirmed("claim", _inputs), do: "Done. Your unlocked REGENT was claimed."

  defp reverted("approve_nft_collection"),
    do: "The approval did not go through and nothing moved. Press Approve NFT collection again."

  defp reverted("approve_exact_usdc"),
    do: "The approval did not go through and nothing moved. Press Approve 80 USDC again."

  defp reverted("redeem"),
    do:
      "The redemption did not go through and nothing moved. This usually means the wallet does not own this Animata, it was already redeemed, an approval had not landed yet, or the wallet holds less than 80 USDC."

  defp reverted("claim"),
    do: "The claim did not go through and nothing moved. There may be no unlocked REGENT yet."

  defp collection(%{"collection" => id}), do: Map.fetch!(@collections, id)

  defp animata(%{"token_id" => token_id} = inputs) do
    {:ok, id} = Steps.token_id(token_id)
    "#{collection(inputs)} ##{id}"
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:signed_in, is_list(assigns.linked))
      |> assign(:mismatch_note, OnchainSteps.mismatch_note(assigns.linked, assigns.active))
      |> assign(:flow_sent, shown(assigns.presses, @every_control))
      |> assign(:claim_sent, shown(assigns.presses, ["claim"]))
      |> assign(:flow_confirming, OnchainSteps.confirming?(assigns.presses, @every_control))
      |> assign(:claim_confirming, OnchainSteps.confirming?(assigns.presses, ["claim"]))
      |> assign(
        :flow_press,
        if(assigns.press_step in [nil | @every_control], do: assigns.press_note)
      )
      |> assign(:claim_press, if(assigns.press_step == "claim", do: assigns.press_note))
      |> assign(:wallet_ready, wallet_ready?(assigns.redemption, assigns.wallet))
      |> assign(:vest_progress, vest_progress(assigns.redemption))
      |> assign(:token_selected, Steps.token_id(assigns.token_id) != :error)
      |> assign_owned_collectibles()

    assigns = assign(assigns, :controls, controls(assigns.step, assigns.token_selected))

    ~H"""
    <section
      id={@id}
      phx-hook="OnchainSteps"
      class="redeem-page"
      aria-busy={to_string(@reading)}
    >
      <section
        id="redeem-intro"
        class="redeem-intro rg-panel rg-panel--surface rg-panel__body"
        aria-labelledby="redemption-page-heading"
      >
        <div class="redeem-intro-copy">
          <p class="redeem-kicker">Animata redemption · Base</p>
          <h1 id="redemption-page-heading" tabindex="-1">Redeem your Animata.</h1>
          <p class="redeem-lede">
            Turn an Animata I or II Pass into Regents Club membership and a seven-day REGENT vest.
          </p>
          <div
            class="redeem-equation"
            aria-label="One Animata plus 80 USDC becomes five million REGENT vested over seven days and one Regents Club membership"
          >
            <span class="redeem-pill">1 Animata</span><b>+</b><span class="redeem-pill">80 USDC</span><b>→</b><span class="redeem-equation-result"><span class="redeem-pill">5 million REGENT</span><b>+</b><span class="redeem-pill">Regents Club</span></span>
          </div>
          <div :if={!@wallet} class="redeem-intro-actions">
            <Regent.Primitives.button
              type="button"
              class="redeem-primary"
              data-account-target={if @signed_in, do: "connect-wallet", else: "sign-in"}
            >
              Connect wallet to redeem
            </Regent.Primitives.button>
          </div>
        </div>

        <Regent.Structure.technical_figure
          id="redeem-intro-media"
          class="redeem-intro-media rg-support-figure"
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
            alt="Animata I and II artwork"
          />
          <:caption>FIG. 02 — Animata I and II artwork</:caption>
        </Regent.Structure.technical_figure>
      </section>

      <div :if={@status == :loading} class="redeem-content" aria-busy="true">
        <section class="redeem-collections rg-panel rg-panel--surface rg-panel__body">
          <h2>Animata collections</h2>
          <div class="redeem-collection-grid">
            <Loading.panel
              :for={name <- ["Animata I", "Animata II", "Regents Club"]}
              id={"redemption-skeleton-#{String.replace(name, " ", "-")}"}
              label={name}
              labels={["Collection supply"]}
              class="redeem-collection-card"
            />
          </div>
        </section>
        <div class="redeem-layout">
          <Loading.panel
            id="redemption-actions-skeleton"
            label="Redemption flow"
            class="redeem-actions rg-panel rg-panel--surface rg-panel__body"
          />
          <Loading.panel
            id="redemption-contract-skeleton"
            label="Contract details"
            class="redeem-overview"
          />
        </div>
      </div>
      <div :if={@status == :error} class="redeem-status">
        <p role="alert">Redemption details are unavailable right now.</p>
        <Regent.Primitives.button
          variant="secondary"
          id="redemption-refresh"
          type="button"
          phx-click="refresh_redemption"
          disabled={@reading}
        >Refresh Data</Regent.Primitives.button>
      </div>

      <div :if={@status == :ready && @redemption} class="redeem-content">
        <section
          id="redemption-collections"
          class="redeem-collections rg-panel rg-panel--surface rg-panel__body"
          aria-labelledby="redemption-collections-heading"
        >
          <div class="redeem-section-heading">
            <div>
              <p class="redeem-kicker">Three connected collections</p><h2 id="redemption-collections-heading">
                Animata I or II + USDC are redeemed for REGENT + Regents Club Digital Pass
              </h2>
            </div>
            <p>Eligible source token IDs are 1–{@redemption.max_source_token_id}.</p>
          </div>
          <div class="redeem-collection-grid">
            <.collection_card
              kind="source"
              index="I"
              title="Animata I"
              count_label="Remaining Passes"
              count={TokenDisplay.count(@redemption.animata_i_supply)}
              href="https://opensea.io/collection/animata"
            />
            <.collection_card
              kind="source"
              index="II"
              title="Animata II"
              count_label="Remaining Passes"
              count={TokenDisplay.count(@redemption.animata_ii_supply)}
              href="https://opensea.io/collection/regent-animata-ii"
            />
            <.collection_card
              kind="result"
              index="RC"
              title="Regents Club"
              count_label="Regents Club Passes claimed"
              count={"#{TokenDisplay.count(@redemption.regents_club_claimed)} / #{TokenDisplay.count(@redemption.regents_club_supply)}"}
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
          <section
            class="redeem-actions rg-panel rg-panel--surface rg-panel__body"
            aria-labelledby="redemption-actions-heading"
          >
            <div class="redeem-section-heading">
              <div>
                <p class="redeem-kicker">Redemption flow</p><h2 id="redemption-actions-heading">
                  {if @wallet, do: "Complete your redemption", else: "Redeem in four signed steps"}
                </h2>
              </div>
              <span :if={@wallet} class="redeem-signer" title={@wallet}><span aria-hidden="true"></span>{RegentFormat.short_address(
                @wallet
              )}</span>
            </div>

            <div :if={!@wallet} class="redeem-connect-panel">
              <p>
                Sign in and connect the wallet that owns your Animata.
              </p>
              <Regent.Primitives.button
                type="button"
                class="redeem-primary"
                data-account-target={if @signed_in, do: "connect-wallet", else: "sign-in"}
              >
                Connect wallet
              </Regent.Primitives.button>
              <ul>
                <li>The page checks ownership and allowances on Base.</li>
                <li>Approvals are requested only when the contract needs them.</li>
                <li>Your wallet confirms every transaction separately.</li>
              </ul>
            </div>

            <.notice :if={@wallet && @notice} notice={@notice} />

            <Loading.panel
              :if={@wallet && !@wallet_ready && @reading}
              id="redemption-wallet-skeleton"
              label="Your collection and vest"
              labels={["Owned Animata", "USDC Balance", "Claimable REGENT"]}
            />

            <div :if={@wallet && !@wallet_ready && !@reading} class="redeem-wallet-recovery">
              <p>
                Your wallet is connected, but its latest Base redemption data could not be loaded.
              </p>
              <div>
                <Regent.Primitives.button
                  variant="secondary"
                  type="button"
                  phx-click="refresh_redemption"
                >Try again</Regent.Primitives.button>
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
                  <Regent.Primitives.field id="redemption-collection" label="Collection">
                    <select
                      id="redemption-collection"
                      name="collection"
                      data-onchain-input="collection"
                    >
                      <option value="animata_i" selected={@collection == "animata_i"}>
                        Animata I
                      </option>
                      <option value="animata_ii" selected={@collection == "animata_ii"}>
                        Animata II
                      </option>
                    </select>
                  </Regent.Primitives.field>
                </div>
                <div>
                  <Regent.Primitives.field id="redemption-token-id" label="Token ID">
                    <input
                      id="redemption-token-id"
                      name="token_id"
                      value={@token_id}
                      maxlength="16"
                      data-onchain-input="token_id"
                      phx-debounce="300"
                      inputmode="numeric"
                      autocomplete="off"
                      placeholder="1–999"
                    />
                  </Regent.Primitives.field>
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
                  <Regent.Primitives.button
                    :for={control <- @controls}
                    id={"redemption-#{control.action}"}
                    type="button"
                    class="redeem-primary"
                    data-onchain-step={@signed_in && control.action}
                    data-account-target={!@signed_in && "sign-in"}
                    data-confirming={@flow_confirming}
                    phx-mounted={JS.ignore_attributes(["data-awaiting-wallet"])}
                    aria-describedby="redemption-step-hint"
                  ><OnchainButton.label label={control.label} /></Regent.Primitives.button>
                </div>
              </section>
              <.mismatch :if={@signed_in} note={@mismatch_note} />
              <.activity
                id="redemption-activity"
                sent={@flow_sent}
                press={@flow_press}
                myself={@myself}
              />
            </div>
          </section>

          <section
            :if={@wallet_ready}
            class="redeem-position rg-panel rg-panel--surface rg-panel__body"
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
            <section
              id="redemption-summary"
              class="redeem-summary"
              aria-label="Redemption account status"
              phx-hook="MotionCount"
              data-variant={RegentsWeb.Motion.standard("count")}
            >
              <.metric label="USDC Balance">
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

            <Regent.Primitives.button
              id="redemption-claim"
              type="button"
              class="redeem-claim"
              data-onchain-step={@signed_in && "claim"}
              data-account-target={!@signed_in && "sign-in"}
              data-confirming={@claim_confirming}
              phx-mounted={JS.ignore_attributes(["data-awaiting-wallet"])}
            ><OnchainButton.label label="Claim unlocked REGENT" /></Regent.Primitives.button>
            <.mismatch :if={@signed_in} note={@mismatch_note} />
            <.activity
              id="redemption-claim-activity"
              sent={@claim_sent}
              press={@claim_press}
              myself={@myself}
            />
            <div class="redeem-position-footer">
              <p class="redeem-snapshot-note">
                <span>Confirmed at Base block {TokenDisplay.count(@redemption.block_number)}.</span><span :if={
                  @reading
                }> Updating from Base…</span>
              </p>
              <Regent.Primitives.button
                variant="secondary"
                id="redemption-refresh"
                type="button"
                phx-click="refresh_redemption"
                disabled={@reading}
                aria-describedby={if(@refresh_block, do: "redemption-refresh-status")}
              >
                {if @reading, do: "Updating…", else: "Refresh Data"}
              </Regent.Primitives.button>
            </div>
          </section>
        </div>

        <section
          :if={@wallet}
          class="redeem-owned rg-panel rg-panel--surface rg-panel__body"
          aria-labelledby="redemption-owned-heading"
        >
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
          <div
            id="redeem-owned-list"
            class="redeem-owned-list"
            phx-hook="MotionList"
            data-layout-id="redeem-owned-list"
            data-children=".redeem-nft-card"
            data-variant={RegentsWeb.Motion.standard("list")}
          >
            <%!-- Selection cards are compound grid controls, not primary action buttons. --%>
            <button
              :for={item <- @visible_animata}
              type="button"
              class="redeem-nft-card"
              data-collection={item.collection}
              data-layout-id={"animata-#{item.collection}-#{item.token_id}"}
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
              :for={item <- @visible_regents_club}
              class="redeem-nft-card redeem-nft-card-club"
              data-layout-id={"club-#{item.token_id}"}
              href={item.href}
              target="_blank"
              rel="noopener noreferrer"
            >
              <span class="redeem-nft-art" aria-hidden="true"></span><span class="redeem-nft-type">Regents Club</span><strong>#{item.token_id}</strong><span class="redeem-nft-action">View on OpenSea ↗</span>
            </a>
          </div>
          <Regent.Primitives.button
            :if={@owned_collectibles_limit < @owned_collectibles_total}
            type="button"
            class="redeem-owned-more"
            phx-click="show_more_collectibles"
          >Show more ({@owned_collectibles_total - @owned_collectibles_limit} remaining)</Regent.Primitives.button>
        </section>

        <Regent.Primitives.disclosure
          id="redeem-contract-details"
          summary="Verification · Redemption contract details"
          class="redeem-contract-details"
        >
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
        </Regent.Primitives.disclosure>
      </div>

      <TransactionReceipt.receipt
        :if={@receipt}
        id="redemption-receipt-dialog"
        title={receipt_title(@receipt)}
        summary={receipt_summary(@receipt)}
        hash={@receipt.hash}
        close_event="close_receipt"
        position={@receipt.position}
        figures={[
          %{label: "Claimable now", key: :claimable, unit: "REGENT"},
          %{label: "Vesting total", key: :vest_pool, unit: "REGENT"}
        ]}
      />
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

  defp step_controls(step)
       when step in [:ready, :nft_redeemed, :nft_not_owned, :insufficient_usdc],
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

  defp step_label(:nft_redeemed, true), do: "This Animata has already been redeemed."

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
  attr :count, :string, required: true
  attr :count_label, :string, required: true
  attr :href, :string, required: true

  defp collection_card(assigns) do
    ~H"""
    <Regent.Structure.capability_card
      class="redeem-collection-card"
      data-kind={@kind}
      title={@title}
      index={@index}
      description={
        if @kind == "source",
          do: "Redemption source · Eligible IDs 1–999",
          else: "Membership result · 1 membership NFT received on redeem"
      }
      image_src={
        if @kind == "source",
          do: "/images/redeem/animata1and2-poster.jpg",
          else: "/images/brand/regents-crown-flat-light.svg"
      }
      image_alt=""
    >
      <:actions>
        <dl class="redeem-collection-copy">
          <div>
            <dt>{@count_label}</dt><dd>{@count}</dd>
          </div>
        </dl>
        <a
          class="rg-button rg-button--secondary"
          href={@href}
          target="_blank"
          rel="noopener noreferrer"
        >View collection on OpenSea ↗</a>
        <.link
          :if={@kind == "result"}
          class="rg-button rg-button--secondary"
          navigate="/redeem/gallery"
        >
          See all 1,998 passes
        </.link>
      </:actions>
    </Regent.Structure.capability_card>
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

  attr :note, :string, default: nil

  # Only the wallet the wallet app has open can act, and only when it is one of
  # the account's own. When it is not, both are named so the person can switch.
  defp mismatch(assigns) do
    ~H"""
    <p :if={@note} class="shell-sending-wallet" role="note">{@note}</p>
    """
  end

  attr :id, :string, required: true
  attr :sent, :list, required: true
  attr :press, :string, default: nil
  attr :myself, :any, required: true

  # What happened to each press, newest first, read on Base by the server.
  defp activity(assigns) do
    ~H"""
    <section
      id={@id}
      class="redeem-activity"
      hidden={@sent == [] and is_nil(@press)}
    >
      <p :if={@press} id={"#{@id}-press"} class="redeem-notice" role="alert">{@press}</p>
      <SubmittedTransactions.list id={@id} sent={@sent} myself={@myself} />
    </section>
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
