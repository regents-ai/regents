defmodule RegentsWeb.StakeLive do
  @moduledoc false
  use Phoenix.Component
  alias RegentsWeb.Components.Loading
  alias RegentsWeb.{TokenDisplay, TokenLinks}

  attr :lease, :map, required: true
  attr :staking, :map, default: nil
  attr :status, :atom, required: true
  attr :wallet, :string, default: nil
  attr :account, :any, default: nil, doc: "the signed-in account, `nil` signed out"
  attr :notice, :map, default: nil
  attr :reading, :boolean, default: false
  attr :shared_reading, :boolean, default: false

  def page(assigns) do
    assigns =
      assigns
      |> assign(:dashboard, staking_dashboard(assigns.staking))
      |> assign(:signed_in, not is_nil(assigns.account))

    ~H"""
    <section
      id="regent-staking"
      class="stake-page"
      aria-busy={to_string(@reading)}
    >
      <header class="stake-heading rg-panel rg-panel--surface rg-panel__body">
        <div class="stake-heading-copy">
          <p class="stake-kicker">REGENT staking · Base</p>
          <h1 id="staking-page-heading" tabindex="-1">Put REGENT to work.</h1>
          <p class="stake-lede">
            Stake REGENT to share in Regents Labs' USDC revenue, in proportion to how much of all REGENT you stake. The business keeps the rest.
          </p>
          <p class="stake-yield-badge">Plus 20% a year in REGENT, for now</p>
          <div class="stake-token-links">
            <a
              class="rg-button stake-buy"
              href={TokenLinks.buy()}
              target="_blank"
              rel="noopener noreferrer"
            ><span class="rg-button__label">
              <span>Buy REGENT</span><span class="visually-hidden">, opens in a new tab</span>
            </span></a>
            <a
              class="rg-button stake-buy"
              href={TokenLinks.chart()}
              target="_blank"
              rel="noopener noreferrer"
            ><span class="rg-button__label">
              <span>View Chart</span><span class="visually-hidden">, opens in a new tab</span>
            </span></a>
          </div>
        </div>
      </header>

      <Regent.Structure.dialog
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
              <Regent.Primitives.address
                id={"staking-supply-#{holding.key}"}
                address={holding.address}
              />
            </dd>
          </div>
        </dl>
        <form method="dialog">
          <Regent.Primitives.button variant="secondary" type="submit" value="close">Done</Regent.Primitives.button>
        </form>
      </Regent.Structure.dialog>

      <Regent.Structure.dialog
        :if={@dashboard && @dashboard.market_cap}
        id="staking-value-dialog"
        class="stake-supply-dialog"
        aria-labelledby="staking-value-heading"
        phx-hook="InfoDialog"
      >
        <p class="stake-dialog-kicker">Circulating MCAP</p>
        <h2 id="staking-value-heading">How the market cap is valued</h2>
        <p class="stake-dialog-summary">
          Circulating REGENT times the price of one REGENT, in US dollars: {@dashboard.market_cap} USD.
        </p>
        <dl class="stake-holdings">
          <div>
            <dt>Circulating REGENT</dt>
            <dd>
              <strong><TokenDisplay.amount amount={@dashboard.circulating_supply} unit="REGENT" /></strong>
              <span>
                Read from Base at block #{TokenDisplay.count(@staking.block_number)}, {read_time(
                  @staking.read_at
                )}.
              </span>
            </dd>
          </div>
          <div>
            <dt>REGENT price</dt>
            <dd>
              <strong>{@dashboard.price} USD</strong>
              <span>
                From DexScreener: REGENT’s price in ETH on the Uniswap pool it trades in, times
                ETH’s price in USDC on Base. Read {read_time(@staking.regent_price_read_at)}.
              </span>
            </dd>
          </div>
        </dl>
        <p class="stake-dialog-summary">
          The price is read on its own schedule, so it was not taken at the same Base block as the supply.
        </p>
        <form method="dialog">
          <Regent.Primitives.button variant="secondary" type="submit" value="close">Done</Regent.Primitives.button>
        </form>
      </Regent.Structure.dialog>

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
          <.live_component
            module={RegentsWeb.StakeActions}
            id="staking-actions"
            lease={@lease}
            staking={@staking}
            status={@status}
            wallet={@wallet}
            account={@account}
            notice={@notice}
            reading={@reading}
          />
        </div>

        <div class="stake-column">
          <dl
            :if={@dashboard}
            id="staking-benefits"
            class="stake-benefit-grid"
            aria-label="Current staking benefits"
            phx-hook="MotionCount"
            data-variant={RegentsWeb.Motion.standard("count")}
          >
            <div class="stake-benefit-card stake-benefit-card-primary">
              <dt>USDC revenue</dt>
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
                <span class="stake-earned-part">
                  <span class="stake-earned-label">Paid to stakers (lifetime)</span>
                  <span class="stake-earned-figure">
                    <TokenDisplay.amount amount={@staking.usdc_credited_to_stakers} unit="USDC" />
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
              <dd :if={@dashboard.market_cap}>{@dashboard.market_cap} USD <.value_info /></dd>
              <dd :if={!@dashboard.market_cap}><TokenDisplay.amount amount={:unavailable} /></dd>
            </div>
            <div class="stake-benefit-card stake-benefit-supply">
              <dt>Total REGENT</dt>
              <dd><TokenDisplay.amount amount={@staking.regent_total_supply} /></dd>
            </div>
          </dl>
          <dl
            :if={!@dashboard}
            id={
              if @status == :loading,
                do: "staking-benefits-skeleton",
                else: "staking-benefits-unavailable"
            }
            class="stake-benefit-grid"
            aria-label="Current staking benefits"
            aria-busy={to_string(@status == :loading)}
          >
            <div class="stake-benefit-card stake-benefit-card-primary">
              <dt>USDC revenue</dt>
              <dd class="stake-earned-split">
                <span
                  :for={label <- ["Last 7 days", "Lifetime", "Paid to stakers (lifetime)"]}
                  class="stake-earned-part"
                >
                  <span class="stake-earned-label">{label}</span>
                  <span class="stake-earned-figure"><.unread loading={@status == :loading} /></span>
                </span>
              </dd>
            </div>
            <div class="stake-benefit-card">
              <dt>REGENT Staked</dt>
              <dd><.unread loading={@status == :loading} kind="metric" /></dd>
            </div>
            <div
              :for={label <- ["Circulating REGENT", "Circulating MCAP", "Total REGENT"]}
              class="stake-benefit-card stake-benefit-supply"
            >
              <dt>{label}</dt>
              <dd><.unread loading={@status == :loading} /></dd>
            </div>
          </dl>

          <.how_it_pays staking={@staking} loading={@status == :loading} />

          <Regent.Structure.section_bar class="rg-support-band">
            <h2 class="rg-section-bar__label">Supply &amp; revenue</h2>
          </Regent.Structure.section_bar>

          <section
            :if={@staking}
            id="staking-contract-overview"
            class="stake-overview rg-panel rg-panel--surface rg-panel__body"
            aria-label="REGENT supply"
          >
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
                Confirmed at Base block #{TokenDisplay.count(@staking.block_number)}, read {RegentFormat.relative_time(
                  @staking.read_at,
                  DateTime.utc_now()
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
            id={
              if @status == :loading,
                do: "staking-contract-skeleton",
                else: "staking-contract-unavailable"
            }
            class="stake-overview rg-panel rg-panel--surface rg-panel__body"
            label="REGENT supply"
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
              <dt>Staking contract</dt><dd>
                <Regent.Primitives.address
                  id="stake-details-contract"
                  address={@staking.contract_address}
                />
              </dd>
            </div>
            <div>
              <dt>REGENT token</dt><dd>
                <Regent.Primitives.address
                  id="stake-details-regent"
                  address={@staking.stake_token_address}
                />
              </dd>
            </div>
            <div>
              <dt>USDC token</dt><dd>
                <Regent.Primitives.address id="stake-details-usdc" address={@staking.usdc_address} />
              </dd>
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

  attr :staking, :map, default: nil
  attr :loading, :boolean, required: true

  # What the contract does with each USDC that reaches it, in the words a
  # stranger needs. The divisor, the reward pool, the Safe's signers and both
  # addresses come from the same Base reading as every other figure here.
  defp how_it_pays(assigns) do
    ~H"""
    <section
      id="staking-how-it-pays"
      class="stake-how rg-panel rg-panel--surface rg-panel__body"
      aria-labelledby="staking-how-heading"
    >
      <h2 id="staking-how-heading" class="stake-section-kicker">How staking pays</h2>
      <ol>
        <li>
          Each USDC payment is split as it arrives. You earn the payment × your staked REGENT ÷
          <.read staking={@staking} key={:revenue_share_denominator} loading={@loading} />.
        </li>
        <li>The business keeps the share of REGENT that isn't staked.</li>
        <li>
          Revenue comes from Credits bought on Base, 10% of Keyfleet Key sales and 10% of Patchbay paid posts.
        </li>
        <li>Claim USDC at any time. There is no lock-up.</li>
        <li>
          REGENT rewards come from a reward pool,
          <.read staking={@staking} key={:reward_inventory} loading={@loading} /> today. The
          Regent Safe (<.signers staking={@staking} loading={@loading} />) sets the rate.
        </li>
        <li :if={@staking}>
          Contracts: staking
          <Regent.Primitives.address id="staking-how-contract" address={@staking.contract_address} />,
          Regent Safe
          <Regent.Primitives.address id="staking-how-safe" address={@staking.treasury_address} />.
        </li>
        <li :if={!@staking}>Contracts: <.unread loading={@loading} /></li>
      </ol>
    </section>
    """
  end

  attr :staking, :map, default: nil
  attr :key, :atom, required: true
  attr :loading, :boolean, required: true

  # A figure inside a sentence is written in words alone, such as 100 billion, so
  # the sentence's own punctuation sits right after it.
  defp read(%{staking: nil} = assigns), do: ~H"<.unread loading={@loading} />"

  defp read(%{staking: staking, key: key} = assigns)
       when is_binary(:erlang.map_get(key, staking)),
       do: ~H"{TokenDisplay.compact(Map.fetch!(@staking, @key))}"

  defp read(assigns), do: ~H"<TokenDisplay.amount amount={:unavailable} />"

  attr :staking, :map, default: nil
  attr :loading, :boolean, required: true

  defp signers(%{staking: %{treasury_threshold: needed, treasury_signer_count: of}} = assigns)
       when is_integer(needed) and is_integer(of),
       do: ~H"{@staking.treasury_threshold} of {@staking.treasury_signer_count} signers"

  defp signers(%{staking: nil} = assigns), do: ~H"<.unread loading={@loading} />"
  defp signers(assigns), do: ~H"<TokenDisplay.amount amount={:unavailable} />"

  attr :loading, :boolean, required: true
  attr :kind, :string, default: "line"

  # A figure not yet read holds its place while it is on its way; once the read
  # has failed it says so, and never stands in as a zero.
  defp unread(%{loading: true} = assigns), do: ~H"<Loading.skeleton kind={@kind} />"
  defp unread(assigns), do: ~H"<TokenDisplay.amount amount={:unavailable} />"

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

  defp value_info(assigns) do
    ~H"""
    <button
      type="button"
      class="stake-info"
      aria-label="How the market cap is valued"
      phx-click={Phoenix.LiveView.JS.dispatch("regents:open", to: "#staking-value-dialog")}
    ><span aria-hidden="true">i</span></button>
    """
  end

  # A clock time with its day, so a price kept from an earlier fetch reads as
  # exactly as old as it is.
  defp read_time(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y at %H:%M UTC")

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
      price: price(staking),
      supply_bps: supply_basis_points(staking)
    }
  end

  # The four holdings the circulating supply leaves out, each with the words for
  # how it comes back. Only the vault has dates; they are the chain's own.
  defp holdings(staking, emission_apr) do
    [
      %{
        key: "clanker-vault",
        name: "Clanker vault",
        address: staking.clanker_vault_address,
        amount: staking.clanker_vault_held,
        release:
          "Locked until #{day(staking.clanker_vault_locked_until)}, then released gradually until #{day(staking.clanker_vault_vested_by)}."
      },
      %{
        key: "treasury",
        name: "Regent treasury",
        address: staking.treasury_address,
        amount: staking.treasury_held,
        release: "Held by the protocol. No release date."
      },
      %{
        key: "animata-redeemer",
        name: "Animata redeemer",
        address: staking.animata_redeemer_address,
        amount: staking.animata_redeemer_held,
        release:
          "Released as Animata I and II holders redeem: 5,000,000 REGENT per token, vesting over seven days. No fixed date."
      },
      %{
        key: "reward-inventory",
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

  # Price × circulating, or nothing: a missing price is unavailable, never a
  # guessed figure.
  defp market_cap(%{regent_price_usd: price, regent_circulating_supply: circulating})
       when is_binary(price) and is_binary(circulating) do
    price |> Decimal.new() |> Decimal.mult(Decimal.new(circulating)) |> TokenDisplay.short()
  end

  defp market_cap(_staking), do: nil

  defp price(%{regent_price_usd: price}) when is_binary(price), do: TokenDisplay.price(price)
  defp price(_staking), do: nil

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

  defp atomic(value) when is_binary(value) do
    case Integer.parse(value) do
      {amount, ""} -> {:ok, amount}
      _ -> :error
    end
  end

  defp atomic(_), do: :error

  attr :notice, :map, required: true

  @doc "A reading's notice: an error is announced at once, anything else politely."
  def notice(assigns) do
    ~H"""
    <p class="stake-notice" role={if @notice.tone == :error, do: "alert", else: "status"}>
      {@notice.message}
    </p>
    """
  end
end
