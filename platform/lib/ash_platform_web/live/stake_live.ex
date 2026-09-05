defmodule AshPlatformWeb.StakeLive do
  @moduledoc false
  use Phoenix.Component
  alias AshPlatformWeb.Components.Shell
  alias AshPlatformWeb.{TokenDisplay, TokenLinks}

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
  attr :actions, :atom, default: :sign_in, values: [:ready, :sign_in, :mismatch]

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
      |> assign(:signer, if(assigns.actions == :ready, do: assigns.wallet))

    ~H"""
    <section
      id="regent-staking"
      phx-hook="StakeWallet"
      class="stake-page"
      aria-busy={to_string(@reading)}
      data-staking-chain-id={@staking && @staking.chain_id}
      data-staking-signer={@signer}
      data-staking-allowance={@signer && stake_allowance(@staking)}
    >
      <header class="stake-heading">
        <div class="stake-heading-copy">
          <p class="stake-kicker">REGENT staking · Base</p>
          <h1 id="staking-page-heading" tabindex="-1">Put REGENT to work.</h1>
          <p class="stake-lede">
            Stake REGENT to participate in contract-distributed USDC revenue rewards and REGENT emissions.
          </p>
          <div class="stake-token-links">
            <a class="stake-buy" href={TokenLinks.buy()} target="_blank" rel="noopener noreferrer">
              <span>Buy REGENT</span> <span aria-hidden="true">↗</span>
            </a>
            <a class="stake-buy" href={TokenLinks.chart()} target="_blank" rel="noopener noreferrer">
              <span>View Chart</span> <span aria-hidden="true">↗</span>
            </a>
            <span class="stake-market-cap">{market_cap_text(@dashboard)}</span>
          </div>
          <div :if={!@wallet} class="stake-heading-actions">
            <button type="button" class="stake-primary" data-account-target="sign-in">
              Connect wallet to stake
            </button>
          </div>
        </div>

        <dl :if={@dashboard} class="stake-benefit-grid" aria-label="Current staking benefits">
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
            <dd><TokenDisplay.amount amount={@dashboard.circulating_supply} /></dd>
          </div>
          <div class="stake-benefit-card stake-benefit-supply">
            <dt>Total REGENT</dt>
            <dd><TokenDisplay.amount amount={@staking.regent_total_supply} /></dd>
          </div>
        </dl>
      </header>

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
        <.notice :if={@notice} notice={@notice} />
        <.shared_refresh :if={@signed_in} reading={@shared_reading} label="Read the contract" />
        <p :if={!@signed_in} class="stake-fine-print">
          Contract data is read once for everyone. A signed-in visitor can ask for a new reading.
        </p>
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
              <span aria-hidden="true"></span>{Shell.short_wallet(@wallet)}
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
            <button type="button" class="stake-primary" data-account-target="sign-in">
              Connect wallet
            </button>
            <p class="stake-fine-print">
              Signing in with Privy connects your wallet. Nothing is sent without your wallet confirmation.
            </p>
          </div>

          <.notice :if={@wallet && @notice} notice={@notice} />

          <div :if={@wallet && !@wallet_ready && @reading} class="stake-wallet-loading" role="status">
            <span class="stake-progress-mark" aria-hidden="true"></span>
            <p>Loading this wallet’s position while contract data remains on screen…</p>
          </div>

          <div :if={@wallet_ready} class="stake-wallet-controls">
            <p :if={is_integer(@staking.wallet_block_number)} class="stake-wallet-block">
              Your position at Base block #{TokenDisplay.count(@staking.wallet_block_number)}.
            </p>
            <p :if={@staking.wallet_block_number == :unavailable} class="stake-wallet-block">
              Your position could not be read just now. Everything else here is current, and every
              action below still goes to your wallet.
            </p>
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
                  phx-debounce="200"
                  aria-describedby="staking-available staking-amount-feedback"
                />
                <span>REGENT</span>
              </div>
              <div class="stake-amount-tools">
                <p id="staking-available">
                  Available
                  <TokenDisplay.amount amount={spendable_figure(@spendable)} unit="REGENT" />
                </p>
                <div>
                  <button
                    type="button"
                    phx-click="fill_staking_amount"
                    phx-value-portion="half"
                    disabled={not fillable?(@spendable, "half")}
                  >50%</button>
                  <button
                    type="button"
                    phx-click="fill_staking_amount"
                    phx-value-portion="max"
                    disabled={not fillable?(@spendable, "max")}
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
                  <dt>Position after</dt><dd>
                    <TokenDisplay.amount amount={@preview.position} unit="REGENT" />
                  </dd>
                </div>
                <div>
                  <dt>USDC Revenue Share</dt><dd>{@preview.revenue_share}</dd>
                </div>
              </dl>

              <p :if={approval_needed?(@staking, @action, @amount)} class="stake-approval-note">
                Your wallet will first request an exact REGENT approval, then the stake transaction.
              </p>
              <button
                class="stake-primary stake-submit"
                type="button"
                data-staking-action={@actions == :ready && @action}
                data-account-target={@actions == :sign_in && "sign-in"}
                phx-click={@actions == :mismatch && "refuse_staking_action"}
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
                  class={if claim.claimable, do: "stake-claim-ready"}
                  data-staking-action={@actions == :ready && claim.action}
                  data-account-target={@actions == :sign_in && "sign-in"}
                  phx-click={@actions == :mismatch && "refuse_staking_action"}
                >{claim.label}<span class="visually-hidden">{claim_state(claim.claimable)}</span></button>
              </div>
            </section>

            <div class="stake-footer">
              <button
                type="button"
                phx-click="refresh_data"
                disabled={@reading || @shared_reading}
              >
                {if @reading || @shared_reading, do: "Updating…", else: "Refresh Data"}
              </button>
            </div>
          </div>
        </section>

        <div class="stake-column">
          <section
            id="staking-revenue-sources"
            class="stake-overview stake-revenue"
            aria-labelledby="staking-revenue-heading"
          >
            <div class="stake-overview-heading">
              <div>
                <p class="stake-section-kicker">Where the USDC comes from</p>
                <h2 id="staking-revenue-heading">USDC Revenue Sources</h2>
              </div>
            </div>

            <div class="stake-revenue-list">
              <details :for={source <- @revenue_sources} class="stake-revenue-source">
                <summary>
                  {source.product}<span class="stake-revenue-caret" aria-hidden="true">▾</span>
                </summary>
                <ul>
                  <li :for={stream <- source.streams}>{stream}</li>
                </ul>
              </details>
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

            <div class="stake-supply">
              <div class="stake-supply-heading">
                <span>REGENT supply</span><strong>{@dashboard.supply.label}</strong>
              </div>
              <div
                id="staking-supply-bar"
                class="stake-supply-bar"
                role="img"
                aria-label={@dashboard.supply.description}
                style={"--circulating-share: #{@dashboard.supply.circulating_share}%; --staked-share: #{@dashboard.supply.staked_share}%"}
              >
                <span class="stake-supply-circulating">
                  <span class="stake-supply-staked"></span>
                </span>
              </div>
              <dl class="stake-supply-facts">
                <div>
                  <dt>Total staked</dt><dd>
                    <TokenDisplay.amount amount={@staking.total_staked} unit="REGENT" />
                  </dd>
                </div>
                <div>
                  <dt>Circulating supply</dt><dd>
                    <TokenDisplay.amount amount={@dashboard.circulating_supply} unit="REGENT" />
                  </dd>
                </div>
                <div>
                  <dt>Total supply</dt><dd>
                    <TokenDisplay.amount amount={@staking.regent_total_supply} unit="REGENT" />
                  </dd>
                </div>
              </dl>
            </div>

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
        </div>
      </div>

      <section
        :if={@status == :ready && @staking}
        class="stake-how-it-works"
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
            The contract currently reports a {@dashboard.emission_apr} emissions APR, subject to onchain changes and available inventory.
          </p>
        </article>
        <article>
          <span aria-hidden="true">03</span><h3>You stay in control</h3><p>
            Stake, unstake, claim, or compound through the connected wallet. Every transaction requires your signature.
          </p>
        </article>
      </section>

      <details :if={@status == :ready && @staking} class="stake-contract-details">
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
                <span>#{TokenDisplay.count(@staking.block_number)}</span><code>{@staking.block_hash}</code>
              </dd>
            </div>
          </dl>
        </div>
      </details>
    </section>
    """
  end

  attr :reading, :boolean, required: true
  attr :label, :string, required: true

  # Re-reading the contract replaces what every visitor is shown, so the server
  # decides whether this click is allowed to; the control only asks.
  defp shared_refresh(assigns) do
    ~H"""
    <button
      type="button"
      class="stake-shared-refresh"
      phx-click="refresh_shared_snapshot"
      disabled={@reading}
    >
      {if @reading, do: "Reading Base…", else: @label}
    </button>
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
    circulating_raw = staking.regent_circulating_supply_raw

    %{
      basescan_url: "https://basescan.org/address/#{staking.contract_address}",
      circulating_supply: to_cents(staking.regent_circulating_supply),
      emission_apr: "#{TokenDisplay.compact(staking.emission_apr_percent)}%",
      market_cap: market_cap(staking),
      supply: supply(staking.total_staked_raw, circulating_raw, staking.regent_total_supply_raw)
    }
  end

  defp market_cap_text(%{market_cap: cap}) when is_binary(cap), do: "#{cap} market cap"
  defp market_cap_text(_dashboard), do: "— market cap"

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

  # One bar carries both proportions: how much of the total supply is
  # circulating, and how much of that circulating supply is staked.
  defp supply(staked_raw, circulating_raw, total_raw) do
    staked_of_circulating = share(staked_raw, circulating_raw)
    circulating_of_total = share(circulating_raw, total_raw)
    label = "#{Decimal.to_string(staked_of_circulating, :normal)}% of circulating supply staked"

    %{
      label: label,
      description:
        "#{label}, and #{Decimal.to_string(circulating_of_total, :normal)}% of total supply circulating",
      staked_share: Decimal.to_string(bounded_share(staked_of_circulating), :normal),
      circulating_share: Decimal.to_string(bounded_share(circulating_of_total), :normal)
    }
  end

  # Two decimals, with the third dropped rather than rounded up, as every other
  # figure on this page does it: a share is allowed to say less than the truth
  # and never more.
  defp share(part_raw, whole_raw) do
    whole = Decimal.new(whole_raw)

    if Decimal.positive?(whole) do
      part_raw
      |> Decimal.new()
      |> Decimal.mult(100)
      |> Decimal.div(whole)
      |> Decimal.round(2, :down)
      |> Decimal.normalize()
    else
      Decimal.new(0)
    end
  end

  defp bounded_share(percentage) do
    cond do
      Decimal.negative?(percentage) -> Decimal.new(0)
      Decimal.gt?(percentage, 100) -> Decimal.new(100)
      true -> percentage
    end
  end

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

  defp fillable?(:unavailable, _portion), do: false
  defp fillable?(spendable, "half"), do: div(spendable, 2) > 0
  defp fillable?(spendable, "max"), do: spendable > 0

  defp wallet_ready?(staking, wallet) when is_map(staking) and is_binary(wallet),
    do: Map.get(staking, :wallet_address) == wallet

  defp wallet_ready?(_, _), do: false

  # An allowance nobody could read is treated as none: the wallet is told to
  # expect the approval step, and the browser asks for one, rather than the
  # press being held back over a figure this page does not have.
  defp approval_needed?(%{wallet_stake_allowance_raw: :unavailable}, "stake", amount),
    do: match?({:ok, _}, AshPlatform.Staking.parse_amount(amount))

  defp approval_needed?(staking, "stake", amount) when is_map(staking) do
    with {:ok, requested} <- AshPlatform.Staking.parse_amount(amount),
         {:ok, allowance} <- atomic(Map.get(staking, :wallet_stake_allowance_raw)) do
      allowance < requested
    else
      _ -> false
    end
  end

  defp approval_needed?(_, _, _), do: false
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

  defp stake_allowance(%{wallet_stake_allowance_raw: allowance}) when is_binary(allowance),
    do: allowance

  defp stake_allowance(_staking), do: nil

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

  defp mode_label("stake"), do: "Stake"
  defp mode_label("unstake"), do: "Unstake"
end
