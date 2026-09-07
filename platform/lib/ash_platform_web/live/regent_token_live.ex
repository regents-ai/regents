defmodule AshPlatformWeb.RegentTokenLive do
  @moduledoc false
  use Phoenix.Component

  alias AshPlatformWeb.{RegentTokenContent, TokenDisplay}

  # Everything on this page is public, dated content from RegentTokenContent.
  # It renders complete in the first HTML, needs no wallet, and every detail
  # sits inside a native disclosure so it is present whether or not it is open.
  def page(assigns) do
    assigns =
      assign(assigns,
        token: RegentTokenContent.token(),
        launch: RegentTokenContent.launch(),
        allocation: RegentTokenContent.allocation(),
        vault: RegentTokenContent.vault(),
        timeline: RegentTokenContent.release_timeline(),
        holders: RegentTokenContent.holders(),
        treasury: RegentTokenContent.treasury(),
        staking: RegentTokenContent.staking(),
        redemption: RegentTokenContent.redemption(),
        policy: RegentTokenContent.original_policy(),
        sources: RegentTokenContent.sources(),
        reviewed_at: RegentTokenContent.reviewed_at()
      )

    ~H"""
    <section id="regent-token" class="regent-token-page">
      <header class="regent-token-heading">
        <p class="regent-token-kicker">REGENT · Base</p>
        <h1 id="regent-token-heading" tabindex="-1">$REGENT</h1>
        <p class="regent-token-lede">
          The Regents Labs token on Base. A fixed 100 billion genesis supply, 40 billion
          of it vaulted until {RegentTokenContent.written_day(@vault.unlock_at)}, and staking
          that shares the USDC revenue actually deposited.
        </p>
        <div class="regent-token-address" aria-label="Token contract">
          <span class="regent-token-kicker">Contract</span>
          <code>{@token.address}</code>
          <div class="regent-token-links">
            <.external href={@sources.token_blockscout}>Blockscout</.external>
            <.external href={@sources.token_basescan}>BaseScan</.external>
            <.external href={@sources.holders}>Holders</.external>
          </div>
        </div>
      </header>

      <dl class="regent-token-facts" aria-label="Key facts">
        <div>
          <dt>Genesis supply</dt>
          <dd><TokenDisplay.amount amount={@token.genesis_supply} unit="REGENT" /></dd>
        </div>
        <div>
          <dt>Launched</dt>
          <dd>
            <time datetime={DateTime.to_iso8601(@launch.at)}>
              {RegentTokenContent.written_day(@launch.at)}
            </time>
          </dd>
        </div>
        <div>
          <dt>Vault release begins</dt>
          <dd>
            <time datetime={DateTime.to_iso8601(@vault.unlock_at)}>
              {RegentTokenContent.written_day(@vault.unlock_at)}
            </time>
          </dd>
        </div>
        <div>
          <dt>Treasury signing</dt>
          <dd>{@treasury.threshold} of {length(@treasury.owners)} owners when checked</dd>
        </div>
      </dl>

      <section
        class="regent-token-panel regent-token-allocation"
        aria-labelledby="regent-token-allocation"
      >
        <h2 id="regent-token-allocation">Genesis allocation</h2>
        <div
          class="regent-token-bar"
          role="img"
          aria-label={Enum.map_join(@allocation, ", ", &"#{&1.percent}% #{&1.label}")}
        >
          <span
            :for={share <- @allocation}
            class={"regent-token-bar-#{share.id}"}
            style={"--share: #{share.percent}"}
          ></span>
        </div>
        <ul class="regent-token-legend">
          <li :for={share <- @allocation} class={"regent-token-legend-#{share.id}"}>
            <span class="regent-token-legend-figure">{share.percent}%</span>
            <span class="regent-token-legend-label">{share.label}</span>
            <span class="regent-token-legend-tokens">
              <TokenDisplay.amount amount={share.tokens} unit="REGENT" />
            </span>
            <span class="regent-token-legend-note">{share.note}</span>
          </li>
        </ul>
        <p class="regent-token-note">
          This is what the launch transaction did at genesis. It is not a reading of who holds
          REGENT today; that is the holders section below.
        </p>

        <details class="regent-token-details">
          <summary>
            <span>Original allocation plan</span>
            <.chevron class="regent-token-chevron" />
          </summary>
          <div class="regent-token-details-body">
            <p>
              The plan Regents Labs published at launch. It is policy, not an onchain rule: the
              buckets are not enforced by any contract, and they do not describe current
              balances.
            </p>
            <div class="regent-token-policy">
              <div>
                <h3>Labs allocation, 40%</h3>
                <ul>
                  <li :for={bucket <- @policy.labs}>{bucket}</li>
                </ul>
              </div>
              <div>
                <h3>Vault, 40%</h3>
                <ul>
                  <li :for={bucket <- @policy.vault}>{bucket}</li>
                </ul>
                <p>
                  Sovereign-agent incentives were stated as an intent; no onchain voting rule
                  enforces them.
                </p>
              </div>
            </div>
          </div>
        </details>
      </section>

      <section class="regent-token-panel regent-token-release" aria-labelledby="regent-token-release">
        <h2 id="regent-token-release">Vault release</h2>
        <ol class="regent-token-timeline">
          <li :for={milestone <- @timeline}>
            <time datetime={DateTime.to_iso8601(milestone.at)}>
              {RegentTokenContent.written(milestone.at)}
            </time>
            <strong>{milestone.title}</strong>
            <span class="regent-token-timeline-figure">
              <TokenDisplay.amount amount={milestone.eligible_tokens} unit="REGENT" /> eligible
            </span>
            <span class="regent-token-timeline-detail">{milestone.detail}</span>
          </li>
        </ol>
        <p class="regent-token-note">
          Each amount is what could be claimed by that moment in total. Being eligible to claim
          is not a claim, a sale or circulation.
        </p>

        <details class="regent-token-details">
          <summary>
            <span>How the vault releases</span>
            <.chevron class="regent-token-chevron" />
          </summary>
          <div class="regent-token-details-body">
            <dl class="regent-token-list">
              <div>
                <dt>Vault contract</dt>
                <dd>
                  <code>{@vault.address}</code>
                  <.external href={@sources.vault_source}>Verified source</.external>
                </dd>
              </div>
              <div>
                <dt>Locked</dt>
                <dd>
                  {div(@vault.lock_seconds, 86_400)} days from {RegentTokenContent.written(
                    @vault.funded_at
                  )}
                </dd>
              </div>
              <div>
                <dt>Vesting</dt>
                <dd>
                  Linear over {div(@vault.vesting_seconds, 86_400)} days, from {RegentTokenContent.written(
                    @vault.unlock_at
                  )} to {RegentTokenContent.written(@vault.fully_vested_at)}
                </dd>
              </div>
              <div>
                <dt>Who claims</dt>
                <dd>
                  Anyone can trigger a claim; the tokens go to the vault's allocation admin,
                  which can change.
                </dd>
              </div>
            </dl>
            <p>
              Schedule read from the verified vault source and the decoded launch input, not
              inferred from month labels.
            </p>
          </div>
        </details>
      </section>

      <section class="regent-token-panel regent-token-holders" aria-labelledby="regent-token-holders">
        <h2 id="regent-token-holders">Largest holders</h2>
        <p class="regent-token-note">
          Indexed balances checked <time datetime={DateTime.to_iso8601(@reviewed_at)}>
            {RegentTokenContent.written(@reviewed_at)}
          </time>. Not a live reading.
          <.external href={@sources.holders}>Current holders</.external>
        </p>
        <table class="regent-token-table">
          <thead>
            <tr>
              <th scope="col">Holder</th>
              <th scope="col">REGENT</th>
              <th scope="col">Of genesis</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={holder <- @holders}>
              <th scope="row">
                <span class="regent-token-holder-label">{holder.label}</span>
                <code>{holder.address}</code>
                <span class="regent-token-holder-description">{holder.description}</span>
              </th>
              <td><TokenDisplay.amount amount={holder.tokens} /></td>
              <td>{RegentTokenContent.percent_of_genesis(holder.tokens)}%</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section
        class="regent-token-panel regent-token-treasury"
        aria-labelledby="regent-token-treasury"
      >
        <h2 id="regent-token-treasury">Regents Labs Treasury</h2>
        <p>
          A Safe on Base. Its owner-signing threshold was {@treasury.threshold} of {length(
            @treasury.owners
          )} when checked. Its balance is separate from the
          time-locked vault allocation, and the allocation plan above is policy, not a lock.
        </p>
        <div class="regent-token-address" aria-label="Treasury Safe">
          <span class="regent-token-kicker">Safe</span>
          <code>{@treasury.address}</code>
          <div class="regent-token-links">
            <.external href={@sources.safe}>Safe app</.external>
            <.external href={RegentTokenContent.explorer_address(@treasury.address)}>
              Blockscout
            </.external>
          </div>
        </div>

        <details class="regent-token-details">
          <summary>
            <span>Signer addresses</span>
            <.chevron class="regent-token-chevron" />
          </summary>
          <div class="regent-token-details-body">
            <p>
              Safe version {@treasury.version}. The signers are these public addresses; no
              person is named here.
            </p>
            <ul class="regent-token-signers">
              <li :for={owner <- @treasury.owners}><code>{owner}</code></li>
            </ul>
          </div>
        </details>
      </section>

      <section
        class="regent-token-panel regent-token-mechanics"
        aria-labelledby="regent-token-mechanics"
      >
        <h2 id="regent-token-mechanics">Staking and redemption</h2>
        <div class="regent-token-cards">
          <article>
            <h3>Staking</h3>
            <p>
              Stake REGENT to share the USDC revenue actually deposited, plus REGENT rewards from
              a funded inventory. Not a guaranteed return.
            </p>
            <.link patch="/stake">Stake</.link>
          </article>
          <article>
            <h3>Redemption</h3>
            <p>
              An Animata redemption pays
              <TokenDisplay.amount
                amount={@redemption.regent_per_redemption}
                unit="REGENT"
              />
              for {@redemption.usdc_price} USDC, released over {div(
                @redemption.vesting_seconds,
                86_400
              )} days. This short vest is separate from
              the long-term vault.
            </p>
            <.link patch="/redeem">Redeem</.link>
          </article>
        </div>

        <details class="regent-token-details">
          <summary>
            <span>How staking rewards are worked out</span>
            <.chevron class="regent-token-chevron" />
          </summary>
          <div class="regent-token-details-body">
            <ul class="regent-token-mechanics-list">
              <li>
                USDC is shared only as it is actually deposited into the staking contract.
                Nothing here promises that every product's revenue reaches it.
              </li>
              <li>
                Each staker's share is worked out against the fixed 100 billion supply. The
                share belonging to unstaked supply goes to the treasury.
              </li>
              <li>
                REGENT rewards are paid from inventory funded separately. The contract owner
                sets the rate, capped at 20% a year, and can change it.
              </li>
            </ul>
          </div>
        </details>

        <details class="regent-token-details">
          <summary>
            <span>Contracts and sources</span>
            <.chevron class="regent-token-chevron" />
          </summary>
          <div class="regent-token-details-body">
            <dl class="regent-token-list">
              <div>
                <dt>Token</dt>
                <dd>
                  <code>{@token.address}</code>
                  <.external href={@sources.token_blockscout}>Blockscout</.external>
                </dd>
              </div>
              <div>
                <dt>Launch</dt>
                <dd>
                  Base block {TokenDisplay.count(@launch.block)}, {RegentTokenContent.written(
                    @launch.at
                  )}
                  <code>{@launch.transaction}</code>
                  <.external href={@sources.launch_transaction}>Transaction</.external>
                  <.external href={@sources.launch_record}>Launch record</.external>
                </dd>
              </div>
              <div>
                <dt>Vault</dt>
                <dd>
                  <code>{@vault.address}</code>
                  <.external href={@sources.vault_source}>Verified source</.external>
                </dd>
              </div>
              <div>
                <dt>Treasury Safe</dt>
                <dd>
                  <code>{@treasury.address}</code>
                  <.external href={@sources.safe}>Safe app</.external>
                </dd>
              </div>
              <div>
                <dt>Staking</dt>
                <dd>
                  <code>{@staking.address}</code>
                  <.external href={RegentTokenContent.explorer_address(@staking.address)}>
                    Blockscout
                  </.external>
                </dd>
              </div>
              <div>
                <dt>Redemption</dt>
                <dd>
                  <code>{@redemption.address}</code>
                  <.external href={RegentTokenContent.explorer_address(@redemption.address)}>
                    Blockscout
                  </.external>
                </dd>
              </div>
            </dl>
            <p>
              Facts reviewed {RegentTokenContent.written(@reviewed_at)} from public Base sources.
              Balances change; the links show the current state.
            </p>
          </div>
        </details>
      </section>
    </section>
    """
  end

  attr :class, :string, required: true

  # A down chevron; the stylesheet turns it over while its disclosure is open.
  defp chevron(assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
      <path
        d="M3 6l5 5 5-5"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :href, :string, required: true
  slot :inner_block, required: true

  defp external(assigns) do
    ~H"""
    <a href={@href} target="_blank" rel="noopener noreferrer">
      {render_slot(@inner_block)} <span aria-hidden="true">↗</span>
    </a>
    """
  end
end
