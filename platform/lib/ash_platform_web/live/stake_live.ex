defmodule AshPlatformWeb.StakeLive do
  @moduledoc false
  use Phoenix.Component
  alias AshPlatform.Staking.Steps
  alias AshPlatformWeb.Components.Loading
  alias AshPlatformWeb.{TokenDisplay, TokenLinks}
  alias Phoenix.LiveView.JS

  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :wallet, :string, default: nil
  attr :action, :string, required: true
  attr :amount, :string, required: true
  attr :notice, :map, default: nil
  attr :reading, :boolean, default: false
  attr :shared_reading, :boolean, default: false
  attr :signed_in, :boolean, default: false
  attr :spendable, :any, default: :unavailable
  attr :amount_notice, :string, default: nil
  attr :available_claims, :map, default: %{}
  attr :actions, :atom, default: :sign_in, values: [:ready, :sign_in]
  attr :sender, :string, default: nil
  attr :form, :map, required: true
  attr :next_step, :string, required: true
  attr :approval_note, :string, default: nil
  attr :sent, :list, default: []
  attr :press, :string, default: nil

  @claims [
    {"claim_usdc", "Claim USDC"},
    {"claim_regent", "Claim REGENT"},
    {"claim_and_restake_regent", "Claim and restake"}
  ]

  # Where the contract's USDC comes from, product by product. This is copy
  # rather than a reading: no chain answers for it, so it is written once here
  # and never assembled from figures the page happens to hold.
  @revenue_sources [
    %{
      product: "Regents Labs",
      streams: [
        "REGENT/ETH Uniswap v4 Pool Fee (0.1-0.3% on volume)",
        "Protocol x402 Services"
      ]
    },
    %{
      product: "Autolaunch",
      streams: [
        "All Tokens Uniswap v4 Hooks (1% on volume)",
        "All Tokens USDC Revenue (2% on volume)"
      ]
    },
    %{
      product: "Techtree",
      streams: [
        "Paid Artifact Revenue (5% on volume)",
        "Protocol Environment Revenue"
      ]
    },
    %{
      product: "Patchbay",
      streams: ["Priority Question Revenue (10% on volume)"]
    }
  ]

  def page(assigns) do
    claims = claims(assigns.available_claims)

    assigns =
      assigns
      |> assign(:dashboard, staking_dashboard(assigns.staking))
      |> assign(:revenue_sources, @revenue_sources)
      |> assign(:wallet_ready, wallet_ready?(assigns.staking, assigns.wallet))
      |> assign(:preview, position_preview(assigns))
      |> assign(:claims, claims)
      |> assign(:receiver, receiver(assigns.form))
      |> assign(:receiver_invalid, receiver_invalid?(assigns.form))

    ~H"""
    <section
      id="regent-staking"
      phx-hook="StakeSteps"
      class="stake-page"
      aria-busy={to_string(@reading)}
      data-staking-mode={@action}
    >
      <header class="stake-heading rg-panel rg-panel--surface rg-panel__body">
        <div class="stake-heading-copy">
          <p class="stake-kicker">REGENT staking · Base</p>
          <h1 id="staking-page-heading" tabindex="-1">Put REGENT to work.</h1>
          <p class="stake-lede">
            Stake REGENT to participate in contract-distributed USDC revenue rewards and REGENT emissions.
          </p>
          <div class="stake-token-links">
            <a
              class="rg-button stake-buy"
              href={TokenLinks.buy()}
              target="_blank"
              rel="noopener noreferrer"
            ><span class="rg-button__label">
              <span>Buy REGENT</span> <span aria-hidden="true">↗</span>
            </span></a>
            <a
              class="rg-button stake-buy"
              href={TokenLinks.chart()}
              target="_blank"
              rel="noopener noreferrer"
            ><span class="rg-button__label">
              <span>View Chart</span> <span aria-hidden="true">↗</span>
            </span></a>
          </div>
        </div>

        <dl
          :if={@dashboard}
          id="staking-benefits"
          class="stake-benefit-grid"
          aria-label="Current staking benefits"
          phx-hook="MotionCount"
          data-variant={AshPlatformWeb.Motion.standard("count")}
        >
          <div class="stake-benefit-card stake-benefit-card-primary">
            <dt>Regent Labs USDC Earned</dt>
            <dd class="stake-earned-split">
              <span class="stake-earned-part">
                <span class="stake-earned-label">Last 7 days</span>
                <span class="stake-earned-figure">
                  <TokenDisplay.amount amount={@staking.usdc_received_7d} unit="USDC" />
                </span>
              </span>
              <span class="stake-earned-part">
                <span class="stake-earned-label">Lifetime</span>
                <span class="stake-earned-figure">
                  <TokenDisplay.amount amount={@staking.usdc_received_lifetime} unit="USDC" />
                </span>
              </span>
            </dd>
          </div>
          <div class="stake-benefit-card">
            <dt>REGENT Staked</dt>
            <dd><TokenDisplay.amount amount={@staking.total_staked} unit="REGENT" /></dd>
          </div>
          <div class="stake-benefit-card stake-benefit-supply">
            <dt>Circulating REGENT</dt>
            <dd><TokenDisplay.amount amount={@dashboard.circulating_supply} /> <.supply_info /></dd>
          </div>
          <div class="stake-benefit-card stake-benefit-supply">
            <dt>Circulating MCAP</dt>
            <dd>{@dashboard.market_cap || "—"}</dd>
          </div>
          <div class="stake-benefit-card stake-benefit-supply">
            <dt>Total REGENT</dt>
            <dd><TokenDisplay.amount amount={@staking.regent_total_supply} /></dd>
          </div>
        </dl>
        <dl
          :if={!@dashboard}
          id="staking-benefits-skeleton"
          class="stake-benefit-grid"
          aria-label="Current staking benefits"
          aria-busy={to_string(@status == :loading)}
        >
          <div class="stake-benefit-card stake-benefit-card-primary">
            <dt>Regent Labs USDC Earned</dt>
            <dd class="stake-earned-split">
              <span :for={label <- ["Last 7 days", "Lifetime"]} class="stake-earned-part">
                <span class="stake-earned-label">{label}</span>
                <span class="stake-earned-figure"><Loading.skeleton /></span>
              </span>
            </dd>
          </div>
          <div class="stake-benefit-card">
            <dt>REGENT Staked</dt>
            <dd><Loading.skeleton kind="metric" /></dd>
          </div>
          <div
            :for={label <- ["Circulating REGENT", "Circulating MCAP", "Total REGENT"]}
            class="stake-benefit-card stake-benefit-supply"
          >
            <dt>{label}</dt>
            <dd><Loading.skeleton /></dd>
          </div>
        </dl>
      </header>

      <dialog
        :if={@dashboard}
        id="staking-supply-dialog"
        class="stake-supply-dialog"
        aria-labelledby="staking-supply-heading"
        phx-hook="InfoDialog"
      >
        <p class="stake-dialog-kicker">Circulating REGENT</p>
        <h2 id="staking-supply-heading">What is not circulating</h2>
        <p class="stake-dialog-summary">
          Of the <TokenDisplay.amount amount={@staking.regent_total_supply} unit="REGENT" />
          in existence, <TokenDisplay.amount amount={@dashboard.held_back} unit="REGENT" />
          is held in the four places below and
          <TokenDisplay.amount amount={@dashboard.circulating_supply} unit="REGENT" />
          circulates. Every figure was read at Base block #{TokenDisplay.count(@staking.block_number)}.
        </p>
        <dl class="stake-holdings">
          <div :for={holding <- @dashboard.holdings}>
            <dt>{holding.name}</dt>
            <dd>
              <strong><TokenDisplay.amount amount={holding.amount} unit="REGENT" /></strong>
              <span>{holding.release}</span>
              <a
                href={"https://basescan.org/address/#{holding.address}"}
                target="_blank"
                rel="noopener noreferrer"
              ><code>{holding.address}</code> <span aria-hidden="true">↗</span></a>
            </dd>
          </div>
        </dl>
        <form method="dialog">
          <Regent.Primitives.button variant="secondary" type="submit" value="close">Done</Regent.Primitives.button>
        </form>
      </dialog>

      <div :if={@status == :error} class="stake-status">
        <p role="alert">Staking details are unavailable right now.</p>
        <.notice :if={@notice} notice={@notice} />
        <.shared_refresh :if={@signed_in} reading={@shared_reading} label="Read the contract" />
        <p :if={!@signed_in} class="stake-fine-print">
          Contract data is read once for everyone. A signed-in visitor can ask for a new reading.
        </p>
      </div>

      <div class="stake-layout">
        <div class="stake-column">
          <section
            class="stake-actions rg-panel rg-panel--surface rg-panel__body"
            aria-labelledby="staking-actions-heading"
          >
            <div class="stake-section-heading">
              <div>
                <p class="stake-section-kicker">Your next move</p>
                <h2 id="staking-actions-heading">
                  {if @wallet, do: "Manage your stake", else: "Stake in three steps"}
                </h2>
              </div>
              <span :if={@wallet} class="stake-signer" title={@wallet}>
                <span aria-hidden="true"></span>{RegentFormat.short_wallet(@wallet)}
              </span>
            </div>

            <div :if={!@wallet} class="stake-connect-flow">
              <ol>
                <li>
                  <span>1</span><p><strong>Connect</strong> an Ethereum wallet.</p>
                </li>
                <li>
                  <span>2</span><p><strong>Choose</strong> how much REGENT to stake.</p>
                </li>
                <li>
                  <span>3</span><p><strong>Confirm</strong> each Base transaction in your wallet.</p>
                </li>
              </ol>
              <Regent.Primitives.button
                type="button"
                class="stake-primary"
                data-account-target={if @signed_in, do: "connect-wallet", else: "sign-in"}
              >
                Connect wallet
              </Regent.Primitives.button>
              <p class="stake-fine-print">
                Signing in connects your wallet. Nothing is sent until you confirm it in your wallet.
              </p>
            </div>

            <.notice :if={@wallet && @notice} notice={@notice} />

            <Loading.panel
              :if={@wallet && !@wallet_ready}
              id="staking-wallet-skeleton"
              label="Your wallet position"
              labels={["Available REGENT", "Currently staked", "Claimable USDC", "Claimable REGENT"]}
              loading={@reading || @status == :loading}
            />

            <div :if={@wallet_ready} id="staking-wallet-controls" class="stake-wallet-controls">
              <p :if={is_integer(@staking.wallet_block_number)} class="stake-wallet-block">
                Your position at Base block #{TokenDisplay.count(@staking.wallet_block_number)}.
              </p>
              <p :if={@staking.wallet_block_number == :unavailable} class="stake-wallet-block">
                Your position could not be read just now. Everything else here is current, and every
                action below still goes to your wallet.
              </p>
              <dl
                id="staking-wallet-summary"
                class="stake-wallet-summary"
                phx-hook="MotionCount"
                data-variant={AshPlatformWeb.Motion.standard("count")}
              >
                <.metric
                  label="Available REGENT"
                  amount={@staking.wallet_token_balance}
                  unit="REGENT"
                />
                <.metric
                  label="Currently staked"
                  amount={@staking.wallet_stake_balance}
                  unit="REGENT"
                />
                <.metric label="Claimable USDC" amount={@staking.wallet_claimable_usdc} unit="USDC" />
                <.metric
                  label="Claimable REGENT"
                  amount={@staking.wallet_claimable_regent}
                  unit="REGENT"
                />
              </dl>

              <div class="stake-mode" role="group" aria-label="Stake or unstake">
                <Regent.Primitives.button
                  :for={mode <- modes()}
                  variant="secondary"
                  type="button"
                  phx-click={
                    if @action == mode,
                      do:
                        Phoenix.LiveView.JS.transition("is-mode-hinted",
                          to: "#staking-amount-form .stake-submit",
                          time: 650,
                          blocking: false
                        ),
                      else: "select_staking_action"
                  }
                  phx-value-mode={mode}
                  aria-pressed={to_string(@action == mode)}
                >{mode_label(mode)}</Regent.Primitives.button>
              </div>

              <form
                id="staking-amount-form"
                phx-change="staking_form_changed"
                phx-hook="MotionTabs"
                data-active={@action}
                data-tabs={Enum.join(modes(), " ")}
                data-variant={AshPlatformWeb.Motion.standard("tabs")}
              >
                <Regent.Primitives.field id="staking-amount" label="Amount">
                  <div class="stake-amount">
                    <input
                      id="staking-amount"
                      name="amount"
                      value={@amount}
                      inputmode="decimal"
                      autocomplete="off"
                      placeholder="0.0"
                      phx-debounce="200"
                      aria-describedby="staking-available staking-amount-feedback"
                    />
                    <span>REGENT</span>
                  </div>
                </Regent.Primitives.field>
                <div class="stake-amount-tools">
                  <div class="stake-amount-action">
                    <Regent.Primitives.button
                      id="staking-primary"
                      class={"stake-primary stake-submit" <> armed_class(@amount)}
                      type="button"
                      data-onchain-step={@actions == :ready && @next_step}
                      data-onchain-form={@actions == :ready && "staking-amount-form"}
                      data-account-target={@actions == :sign_in && "sign-in"}
                      phx-mounted={JS.ignore_attributes(["data-awaiting-wallet"])}
                    ><.press_label label={primary_label(@next_step, @action)} /></Regent.Primitives.button>
                    <p id="staking-available">
                      Available
                      <TokenDisplay.amount amount={spendable_figure(@spendable)} unit="REGENT" />
                    </p>
                  </div>
                  <div class="stake-amount-shortcuts">
                    <Regent.Primitives.button
                      variant="secondary"
                      type="button"
                      phx-click="fill_staking_amount"
                      phx-value-portion="half"
                      disabled={not fillable?(@spendable, "half")}
                    >50%</Regent.Primitives.button>
                    <Regent.Primitives.button
                      variant="secondary"
                      type="button"
                      phx-click="fill_staking_amount"
                      phx-value-portion="max"
                      disabled={not fillable?(@spendable, "max")}
                    >Max</Regent.Primitives.button>
                  </div>
                </div>
                <.signer_note :if={@actions == :ready} sender={@sender} signer={@wallet} />
                <p
                  id="staking-amount-feedback"
                  class="stake-amount-notice"
                  role="status"
                  data-visible={to_string(not is_nil(@amount_notice))}
                >
                  {@amount_notice}
                </p>

                <div
                  id="staking-recipient-controls"
                  class="stake-recipient"
                  hidden={@action != "stake"}
                >
                  <label class="stake-check" for="staking-for-other">
                    <input
                      id="staking-for-other"
                      name="for_other"
                      type="checkbox"
                      value="true"
                      checked={@form.for_other}
                      aria-controls="staking-recipient-fields"
                      aria-expanded={to_string(@form.for_other)}
                    />
                    <span>Stake for a different address</span>
                  </label>
                  <div id="staking-recipient-fields" hidden={!@form.for_other}>
                    <Regent.Primitives.field id="staking-recipient" label="Receiving Ethereum address">
                      <input
                        id="staking-recipient"
                        name="receiver"
                        type="text"
                        value={@form.receiver}
                        autocomplete="off"
                        spellcheck="false"
                        autocapitalize="none"
                        placeholder="0x…"
                        phx-debounce="200"
                        aria-describedby="staking-recipient-error"
                        aria-invalid={to_string(@receiver_invalid)}
                      />
                    </Regent.Primitives.field>
                    <p id="staking-recipient-error" role="status" hidden={!@receiver_invalid}>
                      Enter a valid Ethereum wallet address. ENS names, the zero address and the staking contract are not accepted.
                    </p>
                    <label
                      :if={@receiver}
                      id="staking-recipient-warning"
                      class="stake-check"
                      for="staking-recipient-acknowledged"
                    >
                      <input
                        id="staking-recipient-acknowledged"
                        name="acknowledged"
                        type="checkbox"
                        value="true"
                        checked={Steps.acknowledged?(@form)}
                      />
                      <span id="staking-recipient-warning-text">
                        Warning: the wallet {@receiver} will accrue the USDC revenue and REGENT rewards, and only that wallet may withdraw the tokens.
                      </span>
                    </label>
                  </div>
                </div>

                <dl :if={@preview} class="stake-preview" aria-label="Estimated position after action">
                  <div>
                    <dt>Position after</dt><dd>
                      <TokenDisplay.amount amount={@preview.position} unit="REGENT" />
                    </dd>
                  </div>
                  <div>
                    <dt>USDC Revenue Share</dt><dd>{@preview.revenue_share}</dd>
                  </div>
                </dl>

                <p :if={@actions == :ready && @approval_note} class="stake-approval-note">
                  {@approval_note}
                </p>
              </form>

              <.activity sent={@sent} press={@press} />

              <section class="stake-rewards" aria-labelledby="staking-rewards-heading">
                <div>
                  <p class="stake-section-kicker">Available rewards</p>
                  <h3 id="staking-rewards-heading">Claim or compound</h3>
                </div>
                <div class="stake-button-row">
                  <Regent.Primitives.button
                    :for={claim <- @claims}
                    id={"staking-#{claim.action}"}
                    type="button"
                    class={if claim.claimable, do: "stake-claim-ready"}
                    data-claim={claim.action}
                    data-onchain-step={@actions == :ready && claim.action}
                    data-account-target={@actions == :sign_in && "sign-in"}
                    phx-mounted={JS.ignore_attributes(["data-awaiting-wallet"])}
                  ><.press_label label={claim.label} /><span class="visually-hidden">{claim_state(
                    claim.claimable
                  )}</span></Regent.Primitives.button>
                </div>
                <.signer_note :if={@actions == :ready} sender={@sender} signer={@wallet} />
              </section>

              <div class="stake-footer">
                <Regent.Primitives.button
                  variant="secondary"
                  type="button"
                  phx-click="refresh_data"
                  disabled={@reading || @shared_reading}
                >
                  {if @reading || @shared_reading, do: "Updating…", else: "Refresh Data"}
                </Regent.Primitives.button>
              </div>
            </div>
          </section>

          <section
            class="stake-how-it-works rg-panel rg-panel--surface rg-panel__body"
            aria-labelledby="staking-explainer-heading"
          >
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
                The contract currently reports a
                <span :if={@dashboard}>{@dashboard.emission_apr}</span><span
                  :if={!@dashboard}
                  aria-busy={to_string(@status == :loading)}
                ><Loading.skeleton kind="inline" /></span>
                emissions APR, subject to onchain changes and available inventory.
              </p>
            </article>
            <article>
              <span aria-hidden="true">03</span><h3>You stay in control</h3><p>
                Stake, unstake, claim, or compound through the connected wallet. Every transaction requires your signature.
              </p>
            </article>
          </section>
        </div>

        <div class="stake-column">
          <Regent.Structure.section_bar class="rg-support-band">
            <h2 class="rg-section-bar__label">Supply &amp; revenue</h2>
          </Regent.Structure.section_bar>
          <section
            id="staking-revenue-sources"
            class="stake-overview stake-revenue rg-panel rg-panel--surface rg-panel__body rg-support-panel"
            aria-labelledby="staking-revenue-heading"
          >
            <div class="stake-overview-heading">
              <div>
                <p class="stake-section-kicker">Where the USDC comes from</p>
                <h2 id="staking-revenue-heading">USDC Revenue Sources</h2>
              </div>
            </div>

            <div class="stake-revenue-list">
              <Regent.Primitives.disclosure
                :for={source <- @revenue_sources}
                id={"staking-revenue-#{String.replace(String.downcase(source.product), " ", "-")}"}
                summary={source.product}
                class="stake-revenue-source"
              >
                <ul>
                  <li :for={stream <- source.streams}>{stream}</li>
                </ul>
              </Regent.Primitives.disclosure>
            </div>
          </section>

          <section
            :if={@staking}
            id="staking-contract-overview"
            class="stake-overview rg-panel rg-panel--surface rg-panel__body"
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

            <Regent.Structure.ratio_card
              id="staking-supply-bar"
              title="REGENT supply"
              eyebrow="Base snapshot"
              value_bps={@dashboard.supply_bps}
              label="Circulating supply staked"
              remainder_label="Circulating supply unstaked"
              footer_label="Supply facts · REGENT"
            >
              <:footer>
                <dl class="stake-supply-facts">
                  <div class="rg-ratio-card__tile">
                    <dt>Total staked</dt><dd>
                      <TokenDisplay.amount amount={@staking.total_staked} unit="REGENT" />
                    </dd>
                  </div>
                  <div class="rg-ratio-card__tile">
                    <dt>Circulating supply</dt><dd>
                      <TokenDisplay.amount amount={@dashboard.circulating_supply} unit="REGENT" />
                      <.supply_info />
                    </dd>
                  </div>
                  <div class="rg-ratio-card__tile">
                    <dt>Total supply</dt><dd>
                      <TokenDisplay.amount amount={@staking.regent_total_supply} unit="REGENT" />
                    </dd>
                  </div>
                </dl>
              </:footer>
            </Regent.Structure.ratio_card>
            <p class="stake-fine-print">
              Share of circulating supply, not total supply or reward entitlement. Circulating supply is the total less the Clanker vault, the treasury, the Animata redeemer and the staking reward inventory, all read at the same Base block.
            </p>

            <p class="stake-snapshot-note">
              <span>
                Confirmed at Base block #{TokenDisplay.count(@staking.block_number)}, read {snapshot_age(
                  @staking
                )}.
              </span>
              <span :if={@reading || @shared_reading} class="stake-inline-loading">
                Updating from Base…
              </span>
            </p>

            <.notice :if={!@wallet && @notice} notice={@notice} />
          </section>
          <Loading.panel
            :if={!@staking}
            id="staking-contract-skeleton"
            class="stake-overview rg-panel rg-panel--surface rg-panel__body"
            label="Live contract position"
            labels={["Total staked", "Circulating supply", "Total supply"]}
            loading={@status == :loading}
          />
        </div>
      </div>

      <Regent.Primitives.disclosure
        :if={@status == :ready && @staking}
        id="stake-contract-details"
        summary="Verification · Contract and snapshot details"
        class="stake-contract-details"
      >
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
                <span>#{TokenDisplay.count(@staking.block_number)}</span><code>{@staking.block_hash}</code>
              </dd>
            </div>
          </dl>
        </div>
      </Regent.Primitives.disclosure>
    </section>
    """
  end

  attr :reading, :boolean, required: true
  attr :label, :string, required: true

  # Re-reading the contract replaces what every visitor is shown, so the server
  # decides whether this click is allowed to; the control only asks.
  defp shared_refresh(assigns) do
    ~H"""
    <Regent.Primitives.button
      variant="secondary"
      type="button"
      class="stake-shared-refresh"
      phx-click="refresh_shared_snapshot"
      disabled={@reading}
    >
      {if @reading, do: "Reading Base…", else: @label}
    </Regent.Primitives.button>
    """
  end

  # The small mark beside a circulating figure. It opens the account of what is
  # held back, which every visitor may read; nothing about it touches a wallet.
  defp supply_info(assigns) do
    ~H"""
    <button
      type="button"
      class="stake-info"
      aria-label="What is not circulating"
      phx-click={Phoenix.LiveView.JS.dispatch("regents:open", to: "#staking-supply-dialog")}
    ><span aria-hidden="true">i</span></button>
    """
  end

  @doc "How long ago this contract reading was taken, in plain words."
  def snapshot_age(%{read_at: %DateTime{} = read_at}),
    do: read_at |> DateTime.diff(DateTime.utc_now()) |> abs() |> elapsed()

  def snapshot_age(_staking), do: "just now"

  defp elapsed(seconds) when seconds < 10, do: "moments ago"
  defp elapsed(seconds) when seconds < 60, do: "#{seconds} seconds ago"
  defp elapsed(seconds) when seconds < 120, do: "a minute ago"
  defp elapsed(seconds) when seconds < 3_600, do: "#{div(seconds, 60)} minutes ago"
  defp elapsed(seconds) when seconds < 7_200, do: "an hour ago"
  defp elapsed(seconds), do: "#{div(seconds, 3_600)} hours ago"

  def token_amount(value),
    do:
      value
      |> Decimal.new()
      |> Decimal.div(Decimal.new(Integer.pow(10, 18)))
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)

  defp staking_dashboard(nil), do: nil

  defp staking_dashboard(staking) do
    emission_apr = "#{TokenDisplay.compact(staking.emission_apr_percent)}%"

    %{
      basescan_url: "https://basescan.org/address/#{staking.contract_address}",
      circulating_supply: to_cents(staking.regent_circulating_supply),
      held_back: held_back(staking),
      holdings: holdings(staking, emission_apr),
      emission_apr: emission_apr,
      market_cap: market_cap(staking),
      supply_bps: supply_basis_points(staking)
    }
  end

  # The four holdings the circulating supply leaves out, each with the words for
  # how it comes back. Only the vault has dates; they are the chain's own.
  defp holdings(staking, emission_apr) do
    [
      %{
        name: "Clanker vault",
        address: staking.clanker_vault_address,
        amount: staking.clanker_vault_held,
        release:
          "Locked until #{day(staking.clanker_vault_locked_until)}, then released gradually until #{day(staking.clanker_vault_vested_by)}."
      },
      %{
        name: "Regent treasury",
        address: staking.treasury_address,
        amount: staking.treasury_held,
        release: "Held by the protocol. No release date."
      },
      %{
        name: "Animata redeemer",
        address: staking.animata_redeemer_address,
        amount: staking.animata_redeemer_held,
        release:
          "Released as Animata I and II holders redeem: 5,000,000 REGENT per token, vesting over seven days. No fixed date."
      },
      %{
        name: "Staking reward inventory",
        address: staking.contract_address,
        amount: staking.reward_inventory,
        release:
          "Paid out to stakers as REGENT emissions at the current #{emission_apr} APR. No fixed date."
      }
    ]
  end

  defp day(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y")

  # Everything the supply holds that does not circulate, to the same two
  # decimals as the circulating figure beside it.
  defp held_back(%{regent_total_supply_raw: total, regent_circulating_supply_raw: circulating}) do
    with {:ok, whole} <- atomic(total),
         {:ok, moving} <- atomic(circulating) do
      to_cents(token_amount(whole - moving))
    else
      _ -> nil
    end
  end

  # Price × circulating, or nothing: a missing price is a dash, never a guessed
  # figure.
  defp market_cap(%{regent_price_usd: price, regent_circulating_supply: circulating})
       when is_binary(price) and is_binary(circulating) do
    price |> Decimal.new() |> Decimal.mult(Decimal.new(circulating)) |> TokenDisplay.short()
  end

  defp market_cap(_staking), do: nil

  # The circulating supply moves with every claim and unlock, so the page writes
  # it to the two decimals a person can read out rather than to the eighteen the
  # chain keeps it in. The third decimal is dropped rather than rounded up, as
  # every other figure on this page is.
  defp to_cents(amount) do
    amount
    |> Decimal.new()
    |> Decimal.round(2, :down)
    |> Decimal.to_string(:normal)
  end

  @doc "Read-only circulating-supply ratio from the snapshot's 18-decimal integer strings."
  def supply_basis_points(%{total_staked_raw: staked, regent_circulating_supply_raw: circulating}) do
    with {:ok, part} <- atomic(staked),
         {:ok, whole} <- atomic(circulating),
         true <- whole > 0 and part >= 0 and part <= whole do
      div(part * 10_000, whole)
    else
      _ -> nil
    end
  end

  def supply_basis_points(_), do: nil

  defp position_preview(%{staking: nil}), do: nil

  defp position_preview(%{staking: staking, action: action, amount: amount}) do
    with {:ok, requested} <- AshPlatform.Staking.parse_amount(amount),
         {:ok, current_position} <- atomic(staking.wallet_stake_balance_raw) do
      position =
        if action == "stake",
          do: current_position + requested,
          else: max(current_position - requested, 0)

      %{
        position: token_amount(position),
        revenue_share: revenue_share(position, staking.regent_total_supply_raw)
      }
    else
      _ -> nil
    end
  end

  # Every claim control is offered. The last reading from Base decides which of
  # them is lit, so a reward that is actually waiting stands out before the
  # contract answers for itself.
  defp claims(available) do
    for {action, label} <- @claims do
      %{action: action, label: label, claimable: is_nil(Map.get(available, action))}
    end
  end

  # The glow is a colour, so the same news is carried in the control's name for
  # anyone who does not see it.
  defp claim_state(true), do: "(available)"
  defp claim_state(false), do: "(nothing to claim)"

  # What the amount controls may fill in, or nothing at all when the figure they
  # would count from could not be read. Filling a box is not a wallet request,
  # so these two are the only controls on this page a reading ever quiets.
  defp spendable_figure(:unavailable), do: :unavailable
  defp spendable_figure(spendable), do: token_amount(spendable)

  # An entered amount lights the action the way a pointer resting on it would.
  # It is appearance only; the press reaches the wallet either way.
  defp armed_class(amount) do
    case AshPlatform.Staking.parse_amount(amount) do
      {:ok, _requested} -> " is-armed"
      _invalid -> ""
    end
  end

  defp fillable?(:unavailable, _portion), do: false
  defp fillable?(spendable, "half"), do: div(spendable, 2) > 0
  defp fillable?(spendable, "max"), do: spendable > 0

  defp wallet_ready?(staking, wallet) when is_map(staking) and is_binary(wallet),
    do: Map.get(staking, :wallet_address) == wallet

  defp wallet_ready?(_, _), do: false

  # Revenue is accounted against the whole supply, so a staker's share of it is
  # their position over the total supply. Four decimals are always shown, the
  # fifth dropped rather than rounded up, as every other share on this page is.
  defp revenue_share(position, total_supply_raw) do
    case atomic(total_supply_raw) do
      {:ok, total_supply} when total_supply > 0 ->
        position
        |> Decimal.new()
        |> Decimal.mult(100)
        |> Decimal.div(Decimal.new(total_supply))
        |> Decimal.round(4, :down)
        |> Decimal.to_string(:normal)
        |> Kernel.<>("%")

      _unavailable ->
        "0.0000%"
    end
  end

  defp atomic(value) when is_binary(value) do
    case Integer.parse(value) do
      {amount, ""} -> {:ok, amount}
      _ -> :error
    end
  end

  defp atomic(_), do: :error

  attr :label, :string, required: true
  attr :amount, :any, default: nil
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

  # The address the warning names: one a stake may go to, typed in while staking
  # for someone else.
  defp receiver(%{for_other: true, receiver: input}) do
    case Steps.other_address(input) do
      :error -> nil
      address -> address
    end
  end

  defp receiver(_form), do: nil

  defp receiver_invalid?(%{for_other: true, receiver: input}),
    do: String.trim(input) != "" and Steps.other_address(input) == :error

  defp receiver_invalid?(_form), do: false

  defp primary_label("approve", _action), do: "Approve REGENT"
  defp primary_label(_step, action), do: "#{mode_label(action)} REGENT"

  attr :label, :string, required: true

  # The words swap for "Confirm in wallet" while the wallet has this button's
  # press. The button itself keeps taking presses.
  defp press_label(assigns) do
    ~H"""
    <span data-press-label>{@label}</span><span data-wallet-wait>Confirm in wallet</span>
    """
  end

  attr :sender, :string, default: nil
  attr :signer, :string, default: nil

  # The buttons send from the wallet the account signed in with. When the wallet
  # app has another account selected, both are named so the person can switch.
  defp signer_note(assigns) do
    ~H"""
    <p :if={@sender && @signer} class="shell-sending-wallet" role="note">
      Your wallet app has <span>{RegentFormat.short_wallet(@sender)}</span> selected.
      Buttons here send from <span>{RegentFormat.short_wallet(@signer)}</span>,
      the wallet you signed in with, so switch to it in your wallet app first.
    </p>
    """
  end

  attr :sent, :list, required: true
  attr :press, :string, default: nil

  # What happened to each press, newest first, read on Base by the server.
  defp activity(assigns) do
    ~H"""
    <section id="staking-activity" class="stake-activity" aria-label="Your transactions">
      <p :if={@press} id="staking-press-notice" class="stake-notice" role="alert">{@press}</p>
      <ol :if={@sent != []} class="stake-sent" aria-live="polite">
        <li :for={entry <- @sent} id={"staking-sent-#{entry.hash}"} data-outcome={entry.outcome}>
          <strong>{entry.title}</strong>
          <span>{entry.words}</span>
          <a href={entry.href} target="_blank" rel="noopener noreferrer">
            View on BaseScan <span aria-hidden="true">↗</span>
          </a>
          <Regent.Primitives.button
            :if={entry.outcome == :stalled}
            variant="secondary"
            type="button"
            phx-click="check_staking_step"
            phx-value-hash={entry.hash}
          >Check again</Regent.Primitives.button>
        </li>
      </ol>
    </section>
    """
  end

  defp modes, do: ~w(stake unstake)

  defp mode_label("stake"), do: "Stake"
  defp mode_label("unstake"), do: "Unstake"
end
