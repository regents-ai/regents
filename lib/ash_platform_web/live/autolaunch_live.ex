defmodule AshPlatformWeb.AutolaunchLive do
  @moduledoc false
  use Phoenix.Component

  import AshPlatformWeb.Components.CommentLedger

  attr :route_spec, :map, required: true
  attr :params, :map, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :featured_auctions, :list, required: true
  attr :recent_auctions, :list, required: true
  attr :top_tokens, :list, required: true
  attr :graduated_tokens, :list, required: true
  attr :records, :list, required: true
  attr :record, :map, default: nil
  attr :subject_tokens, :list, required: true
  attr :subject_actions, :list, required: true
  attr :subject_settlements, :list, required: true
  attr :buyback_fields, :map, default: %{"amount_usdc" => "", "minimum_regent_output" => ""}
  attr :buyback_notice, :map, default: nil
  attr :buyback_prepared, :map, default: nil
  attr :buyback_submission, :map, default: nil
  attr :buyback_signing, :boolean, default: false
  attr :subject_payment_fields, :map, default: %{}
  attr :subject_payment_notice, :map, default: nil
  attr :subject_payment_prepared, :map, default: nil
  attr :subject_payment_submission, :map, default: nil
  attr :subject_payment_signing, :boolean, default: false
  attr :bid_positions, :list, required: true
  attr :returnable_positions, :list, required: true
  attr :claimed_token_positions, :list, required: true
  attr :bid_fields, :map, default: %{"amount" => "", "max_price" => ""}
  attr :bid_quote, :map, default: nil
  attr :bid_notice, :map, default: nil
  attr :bid_prepared, :map, default: nil
  attr :bid_submission, :map, default: nil
  attr :bid_signing, :boolean, default: false
  attr :launch_drafts, :list, required: true
  attr :draft_fields, :map, required: true
  attr :draft_notice, :map, default: nil
  attr :regent, :map, default: nil
  attr :status, :atom, required: true
  attr :comments, :list, required: true
  attr :comments_status, :atom, required: true
  attr :comment_notice, :map, default: nil
  attr :comment_request_id, :string, required: true
  attr :comment_draft, :string, required: true
  attr :current_human_id, :integer, default: nil
  attr :comment_admin, :boolean, required: true

  def page(assigns) do
    ~H"""
    <.overview
      :if={@route_spec.route_id == :autolaunch}
      featured_auctions={@featured_auctions}
      recent_auctions={@recent_auctions}
      top_tokens={@top_tokens}
      graduated_tokens={@graduated_tokens}
      status={@status}
    />
    <.collection
      :if={@route_spec.route_id in [:autolaunch_auctions, :autolaunch_tokens]}
      kind={if(@route_spec.route_id == :autolaunch_auctions, do: :auctions, else: :tokens)}
      records={@records}
      status={@status}
    />
    <.subject_collection
      :if={@route_spec.route_id == :autolaunch_subjects}
      records={@records}
      status={@status}
    />
    <.launch_collection
      :if={@route_spec.route_id == :autolaunch_launches}
      records={@records}
      status={@status}
    />
    <.detail
      :if={@route_spec.route_id in [:autolaunch_auction, :autolaunch_token]}
      kind={if(@route_spec.route_id == :autolaunch_auction, do: :auction, else: :token)}
      record_id={
        @params[
          if(@route_spec.route_id == :autolaunch_auction,
            do: "auction_id",
            else: "token_id"
          )
        ]
      }
      record={@record}
      status={@status}
      account_control={@account_control}
      bid_fields={@bid_fields}
      bid_quote={@bid_quote}
      bid_notice={@bid_notice}
      bid_prepared={@bid_prepared}
      bid_submission={@bid_submission}
      bid_signing={@bid_signing}
      bid_positions={@bid_positions}
      comments={@comments}
      comments_status={@comments_status}
      comment_notice={@comment_notice}
      comment_request_id={@comment_request_id}
      comment_draft={@comment_draft}
      current_human_id={@current_human_id}
      comment_admin={@comment_admin}
    />
    <.subject_detail
      :if={@route_spec.route_id == :autolaunch_subject}
      record_id={@params["id"]}
      record={@record}
      tokens={@subject_tokens}
      actions={@subject_actions}
      settlements={@subject_settlements}
      status={@status}
      account_control={@account_control}
      buyback_fields={@buyback_fields}
      buyback_notice={@buyback_notice}
      buyback_prepared={@buyback_prepared}
      buyback_submission={@buyback_submission}
      buyback_signing={@buyback_signing}
      subject_payment_fields={@subject_payment_fields}
      subject_payment_notice={@subject_payment_notice}
      subject_payment_prepared={@subject_payment_prepared}
      subject_payment_submission={@subject_payment_submission}
      subject_payment_signing={@subject_payment_signing}
    />
    <.launch_detail
      :if={@route_spec.route_id == :autolaunch_launch}
      record_id={@params["id"]}
      record={@record}
      status={@status}
    />
    <.holdings
      :if={@route_spec.route_id == :autolaunch_holdings}
      positions={@bid_positions}
      returnable_positions={@returnable_positions}
      claimed_token_positions={@claimed_token_positions}
      status={@status}
    />
    <.create
      :if={@route_spec.route_id == :autolaunch_create}
      account_control={@account_control}
      launch_drafts={@launch_drafts}
      draft_fields={@draft_fields}
      draft_notice={@draft_notice}
      regent={@regent}
    />
    """
  end

  attr :positions, :list, required: true
  attr :returnable_positions, :list, required: true
  attr :claimed_token_positions, :list, required: true
  attr :status, :atom, required: true

  defp holdings(assigns) do
    ~H"""
    <section id="autolaunch-holdings" class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch · Holdings</p>
        <h1>Your holdings</h1>
        <p>Review bid positions and launch tokens connected to your verified wallets.</p>
      </header>

      <p :if={@status == :error} class="autolaunch-empty" role="alert">
        Your holdings are unavailable right now.
      </p>

      <div :if={@status == :ready}>
        <dl>
          <div>
            <dt>Bid positions</dt><dd>{length(@positions)}</dd>
          </div>
          <div>
            <dt>Returnable</dt><dd>{length(@returnable_positions)}</dd>
          </div>
          <div>
            <dt>Held launch tokens</dt><dd>{length(@claimed_token_positions)}</dd>
          </div>
        </dl>

        <section id="autolaunch-bid-positions" aria-labelledby="autolaunch-bid-positions-title">
          <h2 id="autolaunch-bid-positions-title">Bid positions</h2>
          <p :if={@positions == []} class="autolaunch-empty">
            Bids from your verified wallets will appear here.
          </p>
          <ol :if={@positions != []} class="autolaunch-record-list">
            <li :for={position <- @positions} id={"autolaunch-bid-#{position.bid_id}"}>
              <article>
                <p class="autolaunch-kicker">
                  {display_status(position.status)}
                </p>
                <h3>{bid_title(position)}</h3>
                <dl>
                  <div>
                    <dt>Bid amount</dt><dd>{display_text(position.amount)}</dd>
                  </div>
                  <div>
                    <dt>Maximum price</dt><dd>{display_text(position.max_price)}</dd>
                  </div>
                  <div>
                    <dt>Current price</dt>
                    <dd>{display_text(position.current_clearing_price)}</dd>
                  </div>
                  <div>
                    <dt>Estimated tokens</dt>
                    <dd>{display_text(position.estimated_tokens_if_end_now)}</dd>
                  </div>
                  <div>
                    <dt>Wallet</dt><dd>{position.owner_address}</dd>
                  </div>
                  <div>
                    <dt>Updated</dt><dd>{display_time(position.updated_at)}</dd>
                  </div>
                </dl>
                <p :if={position.status == "returnable"}>
                  This position can be returned. No return is started from this page.
                </p>
                <.link patch={"/autolaunch/auctions/#{position.auction_id}"}>
                  View auction
                </.link>
              </article>
            </li>
          </ol>
        </section>

        <section
          id="autolaunch-returnable-positions"
          aria-labelledby="autolaunch-returnable-positions-title"
        >
          <h2 id="autolaunch-returnable-positions-title">Ready to return</h2>
          <p :if={@returnable_positions == []} class="autolaunch-empty">
            No positions are returnable.
          </p>
          <ul :if={@returnable_positions != []}>
            <li :for={position <- @returnable_positions}>
              {bid_title(position)} · {display_text(position.amount)}
            </li>
          </ul>
          <p :if={@returnable_positions != []}>
            Returns are display-only here. This page never opens a wallet or starts a transaction.
          </p>
        </section>

        <section
          id="autolaunch-held-tokens"
          aria-labelledby="autolaunch-held-tokens-title"
        >
          <h2 id="autolaunch-held-tokens-title">Held launch tokens</h2>
          <p :if={@claimed_token_positions == []} class="autolaunch-empty">
            Claimed launch tokens will appear here.
          </p>
          <ol :if={@claimed_token_positions != []} class="autolaunch-record-list">
            <li :for={position <- @claimed_token_positions}>
              <.link patch={"/autolaunch/tokens/#{position.token.id}"}>
                <strong>{position.token.name} · {position.token.symbol}</strong>
                <span>Claimed from {bid_title(position)}</span>
              </.link>
            </li>
          </ol>
        </section>
      </div>
    </section>
    """
  end

  attr :records, :list, required: true
  attr :status, :atom, required: true

  defp launch_collection(assigns) do
    ~H"""
    <section id="autolaunch-launches" class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch</p>
        <h1>Launches</h1>
        <p>Follow public launch progress from preparation through completion.</p>
      </header>
      <.empty_state
        :if={@status == :ready && @records == []}
        copy="No public launches yet."
      />
      <.empty_state
        :if={@status == :error}
        copy="Public launches are unavailable right now."
      />
      <ol :if={@status == :ready && @records != []} class="autolaunch-record-list">
        <li :for={launch <- @records}>
          <.link patch={"/autolaunch/launches/#{launch.job_id}"}>
            <strong>{launch_label(launch)}</strong>
            <span>
              {display_action(launch.status)} · {display_action(launch.step)} · {launch_agent(launch)}
            </span>
          </.link>
        </li>
      </ol>
    </section>
    """
  end

  attr :record_id, :string, required: true
  attr :record, :map, default: nil
  attr :status, :atom, required: true

  defp launch_detail(assigns) do
    ~H"""
    <article
      :if={@status == :ready && @record}
      id="autolaunch-launch-detail"
      class="autolaunch-page"
    >
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch · Launch</p>
        <h1>{launch_label(@record)}</h1>
        <p>Review this launch's recorded progress, identities, and published addresses.</p>
      </header>

      <section aria-labelledby="launch-progress-title">
        <h2 id="launch-progress-title">Progress</h2>
        <dl>
          <div>
            <dt>Status</dt><dd>{display_action(@record.status)}</dd>
          </div>
          <div>
            <dt>Current step</dt><dd>{display_action(@record.step)}</dd>
          </div>
          <div>
            <dt>Chain</dt><dd>{@record.chain_id}</dd>
          </div>
          <div>
            <dt>Launch ID</dt><dd>{@record.job_id}</dd>
          </div>
        </dl>
      </section>

      <section aria-labelledby="launch-identity-title">
        <h2 id="launch-identity-title">Agent and token</h2>
        <dl>
          <div>
            <dt>Agent</dt><dd>{launch_agent(@record)}</dd>
          </div>
          <div>
            <dt>Agent ID</dt><dd>{@record.agent_id}</dd>
          </div>
          <div>
            <dt>Token name</dt><dd>{@record.token_name}</dd>
          </div>
          <div>
            <dt>Token symbol</dt><dd>{@record.token_symbol}</dd>
          </div>
          <div>
            <dt>Launch wallet</dt><dd>{display_text(@record.agent_safe_address)}</dd>
          </div>
        </dl>
      </section>

      <section aria-labelledby="launch-auction-title">
        <h2 id="launch-auction-title">Linked auction</h2>
        <p :if={is_nil(@record.auction_id)} class="autolaunch-empty">
          No auction is linked yet.
        </p>
        <.link
          :if={@record.auction_id}
          patch={"/autolaunch/auctions/#{@record.auction_id}"}
        >
          View linked auction
        </.link>
      </section>

      <section aria-labelledby="launch-addresses-title">
        <h2 id="launch-addresses-title">Published addresses</h2>
        <dl>
          <div>
            <dt>Auction</dt><dd>{display_text(@record.auction_address)}</dd>
          </div>
          <div>
            <dt>Token</dt><dd>{display_text(@record.token_address)}</dd>
          </div>
          <div>
            <dt>Auction rules</dt><dd>{display_text(@record.hook_address)}</dd>
          </div>
          <div>
            <dt>Revenue share</dt>
            <dd>{display_text(@record.revenue_share_splitter_address)}</dd>
          </div>
        </dl>
      </section>

      <section aria-labelledby="launch-times-title">
        <h2 id="launch-times-title">Timeline</h2>
        <dl>
          <div>
            <dt>Started</dt><dd>{display_time(@record.started_at)}</dd>
          </div>
          <div>
            <dt>Finished</dt><dd>{display_time(@record.finished_at)}</dd>
          </div>
          <div>
            <dt>Record added</dt><dd>{display_time(@record.inserted_at)}</dd>
          </div>
          <div>
            <dt>Last updated</dt><dd>{display_time(@record.updated_at)}</dd>
          </div>
        </dl>
      </section>
    </article>

    <section
      :if={@status == :empty}
      id="autolaunch-launch-detail"
      class="autolaunch-page autolaunch-empty"
    >
      <h1>Launch not found</h1>
      <p>No public launch exists at {@record_id}.</p>
      <.link patch="/autolaunch/launches">Return to Launches</.link>
    </section>

    <section
      :if={@status == :error}
      id="autolaunch-launch-detail"
      class="autolaunch-page autolaunch-empty"
      role="alert"
    >
      <h1>Launch unavailable</h1>
      <p>This launch could not be loaded right now.</p>
      <.link patch="/autolaunch/launches">Return to Launches</.link>
    </section>
    """
  end

  attr :records, :list, required: true
  attr :status, :atom, required: true

  defp subject_collection(assigns) do
    ~H"""
    <section id="autolaunch-subjects" class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch</p>
        <h1>Subjects</h1>
        <p>Browse the people and projects that share launch revenue.</p>
      </header>
      <.empty_state
        :if={@status == :ready && @records == []}
        copy="No public subjects yet."
      />
      <.empty_state
        :if={@status == :error}
        copy="Public subjects are unavailable right now."
      />
      <ol :if={@status == :ready && @records != []} class="autolaunch-record-list">
        <li :for={subject <- @records}>
          <.link patch={"/autolaunch/subjects/#{subject.subject_id}"}>
            <strong>{subject_label(subject)}</strong>
            <span>
              {display_text(subject.token_address)} · {display_text(subject.subject_kind)} · Chain {subject.chain_id}
            </span>
          </.link>
        </li>
      </ol>
    </section>
    """
  end

  attr :record_id, :string, required: true
  attr :record, :map, default: nil
  attr :tokens, :list, required: true
  attr :actions, :list, required: true
  attr :settlements, :list, required: true
  attr :status, :atom, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :buyback_fields, :map, required: true
  attr :buyback_notice, :map, default: nil
  attr :buyback_prepared, :map, default: nil
  attr :buyback_submission, :map, default: nil
  attr :buyback_signing, :boolean, required: true
  attr :subject_payment_fields, :map, required: true
  attr :subject_payment_notice, :map, default: nil
  attr :subject_payment_prepared, :map, default: nil
  attr :subject_payment_submission, :map, default: nil
  attr :subject_payment_signing, :boolean, required: true

  defp subject_detail(assigns) do
    ~H"""
    <article
      :if={@status == :ready && @record}
      id="autolaunch-subject-detail"
      class="autolaunch-page"
    >
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch · Subject</p>
        <h1>{subject_label(@record)}</h1>
        <p>
          Revenue sharing and settlement history for this {display_text(@record.subject_kind)}.
        </p>
      </header>

      <section aria-labelledby="subject-identity-title">
        <h2 id="subject-identity-title">Subject details</h2>
        <dl>
          <div>
            <dt>Subject ID</dt><dd>{@record.subject_id}</dd>
          </div>
          <div>
            <dt>Type</dt><dd>{display_text(@record.subject_kind)}</dd>
          </div>
          <div>
            <dt>Chain</dt><dd>{@record.chain_id}</dd>
          </div>
        </dl>
      </section>

      <section aria-labelledby="subject-addresses-title">
        <h2 id="subject-addresses-title">Linked token and addresses</h2>
        <dl>
          <div>
            <dt>Token</dt><dd>{display_text(@record.token_address)}</dd>
          </div>
          <div>
            <dt>Revenue split</dt><dd>{display_text(@record.splitter_address)}</dd>
          </div>
          <div>
            <dt>Revenue entry</dt><dd>{display_text(@record.ingress_address)}</dd>
          </div>
          <div>
            <dt>Treasury</dt><dd>{display_text(@record.treasury_address)}</dd>
          </div>
          <div>
            <dt>Factory</dt><dd>{display_text(@record.factory_address)}</dd>
          </div>
          <div>
            <dt>Creator</dt><dd>{display_text(@record.creator_address)}</dd>
          </div>
        </dl>
      </section>

      <section aria-labelledby="subject-revenue-title">
        <h2 id="subject-revenue-title">Revenue</h2>
        <dl>
          <div>
            <dt>Staker pool share</dt><dd>{display_bps(@record.staker_pool_bps)}</dd>
          </div>
          <div>
            <dt>Starting protocol share</dt>
            <dd>{display_bps(@record.protocol_skim_bps_snapshot)}</dd>
          </div>
          <div>
            <dt>Current protocol share</dt>
            <dd>{display_bps(@record.current_protocol_skim_bps)}</dd>
          </div>
          <div>
            <dt>Protocol fees</dt>
            <dd>{display_text(@record.protocol_fee_usdc_total_raw)}</dd>
          </div>
          <div>
            <dt>Regent emissions</dt>
            <dd>{display_text(@record.regent_emission_total_raw)}</dd>
          </div>
        </dl>
      </section>

      <section id="subject-related-tokens" aria-labelledby="subject-related-tokens-title">
        <h2 id="subject-related-tokens-title">Related tokens</h2>
        <p :if={@tokens == []} class="autolaunch-empty">No related tokens yet.</p>
        <ol :if={@tokens != []} class="autolaunch-record-list">
          <li :for={token <- @tokens}>
            <.link patch={"/autolaunch/tokens/#{token.id}"}>
              <strong>{token.name} · {token.symbol}</strong>
              <span>{token.summary || "No public token summary yet."}</span>
            </.link>
          </li>
        </ol>
      </section>

      <section id="subject-recent-actions" aria-labelledby="subject-recent-actions-title">
        <h2 id="subject-recent-actions-title">Recent actions</h2>
        <.subject_action_list
          actions={@actions}
          empty_copy="No subject actions yet."
          id_prefix="subject-action"
        />
      </section>

      <section id="subject-settlement-history" aria-labelledby="subject-settlement-title">
        <h2 id="subject-settlement-title">Settlement history</h2>
        <dl>
          <div>
            <dt>Pending buyback</dt>
            <dd>{display_text(@record.pending_buyback_usdc_raw)}</dd>
          </div>
          <div>
            <dt>Ready to settle</dt>
            <dd>{if(settlement_ready?(@record), do: "Yes", else: "No")}</dd>
          </div>
        </dl>

        <.subject_action_list
          actions={@settlements}
          empty_copy="No settlements yet."
          id_prefix="subject-settlement"
        />
      </section>

      <.buyback_wallet
        record={@record}
        account_control={@account_control}
        fields={@buyback_fields}
        notice={@buyback_notice}
        prepared={@buyback_prepared}
        submission={@buyback_submission}
        signing={@buyback_signing}
      />

      <.subject_payment_wallet
        record={@record}
        account_control={@account_control}
        fields={@subject_payment_fields}
        notice={@subject_payment_notice}
        prepared={@subject_payment_prepared}
        submission={@subject_payment_submission}
        signing={@subject_payment_signing}
      />
    </article>

    <section
      :if={@status == :empty}
      id="autolaunch-subject-detail"
      class="autolaunch-page autolaunch-empty"
    >
      <h1>Subject not found</h1>
      <p>No public subject exists at {@record_id}.</p>
      <.link patch="/autolaunch/subjects">Return to Subjects</.link>
    </section>

    <section
      :if={@status == :error}
      id="autolaunch-subject-detail"
      class="autolaunch-page autolaunch-empty"
      role="alert"
    >
      <h1>Subject unavailable</h1>
      <p>This subject could not be loaded right now.</p>
      <.link patch="/autolaunch/subjects">Return to Subjects</.link>
    </section>
    """
  end

  attr :record, :map, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :fields, :map, required: true
  attr :notice, :map, default: nil
  attr :prepared, :map, default: nil
  attr :submission, :map, default: nil
  attr :signing, :boolean, required: true

  defp buyback_wallet(assigns) do
    ~H"""
    <section
      id="subject-buyback-wallet"
      phx-hook="AutolaunchBuybackWallet"
      aria-labelledby="subject-buyback-wallet-title"
    >
      <p class="autolaunch-kicker">Wallet action</p>
      <h2 id="subject-buyback-wallet-title">Settle a pending buyback</h2>
      <p>
        Regent checks the current market guardrails and prepares the revenue-router request.
        Your verified wallet reviews and signs the settlement.
      </p>

      <p :if={@account_control.kind == :sign_in} class="autolaunch-empty">
        Sign in to prepare a buyback settlement from a verified wallet.
      </p>

      <form
        :if={@account_control.kind == :signed_in}
        id="subject-buyback-form"
        phx-submit="prepare_autolaunch_buyback"
      >
        <label>
          <span>USDC amount</span>
          <input
            type="text"
            inputmode="decimal"
            name="buyback[amount_usdc]"
            value={@fields["amount_usdc"]}
            autocomplete="off"
            required
          />
        </label>
        <label>
          <span>Minimum REGENT output</span>
          <input
            type="text"
            inputmode="decimal"
            name="buyback[minimum_regent_output]"
            value={@fields["minimum_regent_output"]}
            autocomplete="off"
            required
          />
        </label>
        <button type="submit" disabled={not is_nil(@submission)}>Review settlement</button>
      </form>

      <p
        :if={@notice}
        class={"autolaunch-draft-notice autolaunch-draft-notice--#{@notice.tone}"}
        role={if(@notice.tone == :error, do: "alert", else: "status")}
      >
        {@notice.message}
      </p>

      <section :if={@prepared} id="subject-buyback-review" aria-label="Wallet action review">
        <p class="autolaunch-kicker">Review before signing</p>
        <h3>Settle treasury buyback</h3>
        <p>{@prepared.risk_copy}</p>
        <dl>
          <div>
            <dt>USDC amount</dt><dd>{buyback_argument(@prepared, :amount_usdc)}</dd>
          </div>
          <div>
            <dt>Minimum REGENT output</dt>
            <dd>{buyback_argument(@prepared, :minimum_regent_output)}</dd>
          </div>
          <div>
            <dt>Subject</dt><dd>{buyback_argument(@prepared, :subject_id)}</dd>
          </div>
          <div>
            <dt>Treasury</dt><dd>{buyback_argument(@prepared, :treasury)}</dd>
          </div>
          <div>
            <dt>Network</dt><dd>Base</dd>
          </div>
          <div>
            <dt>Wallet</dt><dd>{@prepared.expected_signer}</dd>
          </div>
          <div>
            <dt>Contract</dt><dd>{@prepared.to}</dd>
          </div>
          <div>
            <dt>Native value</dt><dd>0 ETH</dd>
          </div>
        </dl>
        <button
          :if={is_nil(@submission)}
          type="button"
          phx-click="sign_prepared_autolaunch_buyback"
          phx-value-action-id={@prepared.action_id}
          disabled={@signing}
        >
          {if @signing, do: "Waiting for wallet", else: "Confirm in wallet"}
        </button>
        <button
          :if={is_nil(@submission)}
          type="button"
          phx-click="cancel_autolaunch_buyback_review"
        >
          Cancel review
        </button>
        <button
          :if={@submission && @submission[:transaction_hash]}
          type="button"
          phx-click="retry_autolaunch_buyback_confirmation"
          disabled={@signing}
        >
          Retry confirmation
        </button>
      </section>
    </section>
    """
  end

  attr :record, :map, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :fields, :map, required: true
  attr :notice, :map, default: nil
  attr :prepared, :map, default: nil
  attr :submission, :map, default: nil
  attr :signing, :boolean, required: true

  defp subject_payment_wallet(assigns) do
    ~H"""
    <section
      id="subject-payment-wallet"
      phx-hook="AutolaunchSubjectPaymentWallet"
      aria-labelledby="subject-payment-wallet-title"
    >
      <p class="autolaunch-kicker">Wallet actions</p>
      <h2 id="subject-payment-wallet-title">Payment links, revenue, and subject staking</h2>
      <p>
        Regent prepares each request from this subject's stored Base contracts. Your verified
        subject-owner wallet reviews and signs it.
      </p>

      <p :if={@account_control.kind == :sign_in} class="autolaunch-empty">
        Sign in to prepare subject wallet actions.
      </p>

      <div :if={@account_control.kind == :signed_in} id="subject-payment-forms">
        <form id="subject-payment-link-create-form" phx-submit="prepare_autolaunch_subject_payment">
          <input type="hidden" name="subject_payment[action]" value="create_payment_link" />
          <h3>Create a payment link</h3>
          <label>
            <span>Label</span>
            <input
              type="text"
              name="subject_payment[label]"
              value={subject_payment_field(@fields, "label")}
              maxlength="96"
              required
            />
          </label>
          <label>
            <span>Link kind</span>
            <select name="subject_payment[canonical]">
              <option value="false">Standard</option>
              <option value="true">Canonical</option>
            </select>
          </label>
          <button type="submit" disabled={subject_payment_locked?(@prepared, @submission)}>
            Review payment link
          </button>
        </form>

        <form
          id="subject-payment-link-canonical-form"
          phx-submit="prepare_autolaunch_subject_payment"
        >
          <input
            type="hidden"
            name="subject_payment[action]"
            value="set_payment_link_canonical"
          />
          <h3>Set canonical status</h3>
          <label>
            <span>Payment-link address</span>
            <input type="text" name="subject_payment[receiver]" required autocomplete="off" />
          </label>
          <label>
            <span>Canonical</span>
            <select name="subject_payment[canonical]">
              <option value="true">Yes</option>
              <option value="false">No</option>
            </select>
          </label>
          <button type="submit" disabled={subject_payment_locked?(@prepared, @submission)}>
            Review canonical change
          </button>
        </form>

        <form id="subject-payment-link-state-form" phx-submit="prepare_autolaunch_subject_payment">
          <input type="hidden" name="subject_payment[action]" value="set_payment_link_state" />
          <h3>Set payment-link receiver state</h3>
          <label>
            <span>Payment-link address</span>
            <input type="text" name="subject_payment[receiver]" required autocomplete="off" />
          </label>
          <label>
            <span>Active</span>
            <select name="subject_payment[active]">
              <option value="true">Yes</option>
              <option value="false">No</option>
            </select>
          </label>
          <label>
            <span>Replacement address (optional)</span>
            <input type="text" name="subject_payment[replacement]" autocomplete="off" />
          </label>
          <button type="submit" disabled={subject_payment_locked?(@prepared, @submission)}>
            Review receiver change
          </button>
        </form>

        <form
          :if={@record.ingress_address}
          id="subject-ingress-sweep-form"
          phx-submit="prepare_autolaunch_subject_payment"
        >
          <input type="hidden" name="subject_payment[action]" value="sweep_usdc" />
          <h3>Sweep recorded revenue ingress</h3>
          <p>{@record.ingress_address}</p>
          <button type="submit" disabled={subject_payment_locked?(@prepared, @submission)}>
            Review USDC sweep
          </button>
        </form>

        <form id="subject-stake-form" phx-submit="prepare_autolaunch_subject_payment">
          <input type="hidden" name="subject_payment[action]" value="stake" />
          <h3>Stake subject tokens</h3>
          <label>
            <span>Token amount</span>
            <input
              type="text"
              inputmode="decimal"
              name="subject_payment[amount]"
              required
              autocomplete="off"
            />
          </label>
          <label>
            <span>Receiver (optional; defaults to your wallet)</span>
            <input type="text" name="subject_payment[receiver]" autocomplete="off" />
          </label>
          <p>
            This uses an exact token approval for the reviewed amount. Your wallet may retain that
            allowance if the stake is not submitted; review or revoke it before preparing again.
          </p>
          <button type="submit" disabled={subject_payment_locked?(@prepared, @submission)}>
            Review stake
          </button>
        </form>

        <form id="subject-unstake-form" phx-submit="prepare_autolaunch_subject_payment">
          <input type="hidden" name="subject_payment[action]" value="unstake" />
          <h3>Unstake subject tokens</h3>
          <label>
            <span>Token amount</span>
            <input
              type="text"
              inputmode="decimal"
              name="subject_payment[amount]"
              required
              autocomplete="off"
            />
          </label>
          <button type="submit" disabled={subject_payment_locked?(@prepared, @submission)}>
            Review unstake
          </button>
        </form>

        <form id="subject-claim-usdc-form" phx-submit="prepare_autolaunch_subject_payment">
          <input type="hidden" name="subject_payment[action]" value="claim_usdc" />
          <h3>Claim subject USDC</h3>
          <button type="submit" disabled={subject_payment_locked?(@prepared, @submission)}>
            Review USDC claim
          </button>
        </form>
      </div>

      <p
        :if={@notice}
        class={"autolaunch-draft-notice autolaunch-draft-notice--#{@notice.tone}"}
        role={if(@notice.tone == :error, do: "alert", else: "status")}
      >
        {@notice.message}
      </p>

      <section :if={@prepared} id="subject-payment-review" aria-label="Wallet action review">
        <p class="autolaunch-kicker">Review before signing</p>
        <h3>{subject_payment_title(@prepared.action)}</h3>
        <p>{@prepared.risk_copy}</p>
        <dl>
          <div>
            <dt>Subject</dt><dd>{subject_payment_argument(@prepared, :subject_id)}</dd>
          </div>
          <div>
            <dt>Network</dt><dd>Base</dd>
          </div>
          <div>
            <dt>Wallet</dt><dd>{@prepared.expected_signer}</dd>
          </div>
          <div>
            <dt>Contract</dt><dd>{@prepared.to}</dd>
          </div>
          <div>
            <dt>Native value</dt><dd>0 ETH</dd>
          </div>
          <div :if={subject_payment_argument(@prepared, :label)}>
            <dt>Label</dt><dd>{subject_payment_argument(@prepared, :label)}</dd>
          </div>
          <div :if={subject_payment_argument(@prepared, :receiver)}>
            <dt>Receiver</dt><dd>{subject_payment_argument(@prepared, :receiver)}</dd>
          </div>
          <div
            :if={subject_payment_argument(@prepared, :replacement)}
            id="subject-payment-review-replacement"
          >
            <dt>Replacement</dt><dd>{subject_payment_argument(@prepared, :replacement)}</dd>
          </div>
          <div :if={subject_payment_argument(@prepared, :amount)}>
            <dt>Token amount</dt><dd>{subject_payment_argument(@prepared, :amount)}</dd>
          </div>
          <div :if={not is_nil(subject_payment_argument(@prepared, :canonical))}>
            <dt>Canonical</dt>
            <dd>{yes_no(subject_payment_argument(@prepared, :canonical))}</dd>
          </div>
          <div :if={not is_nil(subject_payment_argument(@prepared, :active))}>
            <dt>Active</dt><dd>{yes_no(subject_payment_argument(@prepared, :active))}</dd>
          </div>
        </dl>
        <p :if={@prepared.approval}>
          First approve exactly {@prepared.approval.amount} atomic units of the stored subject token.
          If you stop after approval, review or revoke that allowance in your wallet.
        </p>
        <button
          :if={is_nil(@submission)}
          type="button"
          phx-click="sign_prepared_autolaunch_subject_payment"
          phx-value-action-id={@prepared.action_id}
          disabled={@signing}
        >
          {if @signing, do: "Waiting for wallet", else: "Confirm in wallet"}
        </button>
        <button
          :if={is_nil(@submission)}
          type="button"
          phx-click="cancel_autolaunch_subject_payment_review"
        >
          Cancel review
        </button>
        <button
          :if={
            @submission && @submission[:approval_transaction_hash] &&
              is_nil(@submission[:transaction_hash])
          }
          type="button"
          phx-click="retry_autolaunch_subject_payment_approval_verification"
          disabled={@signing}
        >
          Retry approval verification
        </button>
        <button
          :if={@submission && @submission[:transaction_hash]}
          type="button"
          phx-click="retry_autolaunch_subject_payment_confirmation"
          disabled={@signing}
        >
          Retry confirmation
        </button>
      </section>
    </section>
    """
  end

  attr :actions, :list, required: true
  attr :empty_copy, :string, required: true
  attr :id_prefix, :string, required: true

  defp subject_action_list(assigns) do
    ~H"""
    <p :if={@actions == []} class="autolaunch-empty">{@empty_copy}</p>
    <ol :if={@actions != []} class="autolaunch-record-list">
      <li :for={action <- @actions} id={"#{@id_prefix}-#{action.id}"}>
        <article>
          <h3>{display_action(action.action)}</h3>
          <dl>
            <div>
              <dt>Status</dt><dd>{display_text(action.status)}</dd>
            </div>
            <div>
              <dt>Owner</dt><dd>{display_text(action.owner_address)}</dd>
            </div>
            <div>
              <dt>Chain</dt><dd>{action.chain_id}</dd>
            </div>
            <div>
              <dt>Transaction</dt><dd>{display_text(action.tx_hash)}</dd>
            </div>
            <div>
              <dt>Amount</dt><dd>{display_text(action.amount)}</dd>
            </div>
            <div>
              <dt>Block</dt><dd>{display_text(action.block_number)}</dd>
            </div>
            <div>
              <dt>Time</dt><dd>{display_time(action.inserted_at)}</dd>
            </div>
          </dl>
        </article>
      </li>
    </ol>
    """
  end

  attr :featured_auctions, :list, required: true
  attr :recent_auctions, :list, required: true
  attr :top_tokens, :list, required: true
  attr :graduated_tokens, :list, required: true
  attr :status, :atom, required: true

  defp overview(assigns) do
    ~H"""
    <section id="autolaunch-overview" class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch</p>
        <h1>Launch with public proof</h1>
        <p>
          Discover auctions, follow graduated tokens, and create a launch whose money actions
          remain under wallet control.
        </p>
        <nav class="autolaunch-actions" aria-label="Autolaunch actions">
          <.link patch="/autolaunch/auctions">Browse auctions</.link>
          <.link patch="/autolaunch/tokens">Browse tokens</.link>
          <.link patch="/autolaunch/launches">Browse launches</.link>
          <.link patch="/autolaunch/holdings">View holdings</.link>
          <.link patch="/autolaunch/create">Create a launch</.link>
        </nav>
      </header>

      <div class="autolaunch-market-grid">
        <.market_section title="Featured auctions" kind={:auction} records={@featured_auctions} />
        <.market_section title="Recently created" kind={:auction} records={@recent_auctions} />
        <.market_section title="Top tokens" kind={:token} records={@top_tokens} />
        <.market_section title="Recently graduated" kind={:token} records={@graduated_tokens} />
      </div>
      <p :if={@status == :error} class="autolaunch-empty" role="alert">
        Public launch records are unavailable right now.
      </p>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :kind, :atom, required: true
  attr :records, :list, required: true

  defp market_section(assigns) do
    ~H"""
    <section class="autolaunch-market-section">
      <h2>{@title}</h2>
      <p :if={@records == []}>No public records yet.</p>
      <ol :if={@records != []} class="autolaunch-record-list">
        <li :for={record <- @records}>
          <.link patch={record_path(@kind, record.id)}>
            <strong>{record_label(@kind, record)}</strong>
            <span>{record.summary || record_fallback(@kind)}</span>
          </.link>
        </li>
      </ol>
    </section>
    """
  end

  attr :kind, :atom, required: true
  attr :records, :list, required: true
  attr :status, :atom, required: true

  defp collection(assigns) do
    assigns =
      assign(assigns,
        title: if(assigns.kind == :auctions, do: "Auctions", else: "Tokens"),
        copy:
          if(
            assigns.kind == :auctions,
            do: "Active and completed auctions will appear here.",
            else: "Graduated and actively traded tokens will appear here."
          )
      )

    ~H"""
    <section id={"autolaunch-#{@kind}"} class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch</p>
        <h1>{@title}</h1>
        <p>{@copy}</p>
      </header>
      <.empty_state :if={@status == :ready && @records == []} copy="No public records yet." />
      <.empty_state :if={@status == :error} copy="Public records are unavailable right now." />
      <ol :if={@status == :ready && @records != []} class="autolaunch-record-list">
        <li :for={record <- @records}>
          <.link patch={record_path(collection_record_kind(@kind), record.id)}>
            <strong>{record_label(collection_record_kind(@kind), record)}</strong>
            <span>{record.summary || record_fallback(collection_record_kind(@kind))}</span>
          </.link>
        </li>
      </ol>
    </section>
    """
  end

  attr :kind, :atom, required: true
  attr :record_id, :string, required: true
  attr :record, :map, default: nil
  attr :status, :atom, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :bid_fields, :map, required: true
  attr :bid_quote, :map, default: nil
  attr :bid_notice, :map, default: nil
  attr :bid_prepared, :map, default: nil
  attr :bid_submission, :map, default: nil
  attr :bid_signing, :boolean, required: true
  attr :bid_positions, :list, required: true
  attr :comments, :list, required: true
  attr :comments_status, :atom, required: true
  attr :comment_notice, :map, default: nil
  attr :comment_request_id, :string, required: true
  attr :comment_draft, :string, required: true
  attr :current_human_id, :integer, default: nil
  attr :comment_admin, :boolean, required: true

  defp detail(assigns) do
    assigns = assign(assigns, :title, if(assigns.kind == :auction, do: "Auction", else: "Token"))

    ~H"""
    <article
      :if={@status == :ready && @record}
      id={"autolaunch-#{@kind}-detail"}
      class="autolaunch-page"
    >
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch · {@title}</p>
        <h1>{record_label(@kind, @record)}</h1>
        <p>{@record.summary || record_fallback(@kind)}</p>
      </header>
      <.auction_wallet
        :if={@kind == :auction}
        record={@record}
        account_control={@account_control}
        fields={@bid_fields}
        quote={@bid_quote}
        notice={@bid_notice}
        prepared={@bid_prepared}
        submission={@bid_submission}
        signing={@bid_signing}
        positions={@bid_positions}
      />
      <.comment_ledger
        comments={@comments}
        status={@comments_status}
        notice={@comment_notice}
        request_id={@comment_request_id}
        draft={@comment_draft}
        current_human_id={@current_human_id}
        admin={@comment_admin}
      />
    </article>

    <section
      :if={@status in [:empty, :error]}
      id={"autolaunch-#{@kind}-detail"}
      class="autolaunch-page autolaunch-empty"
      role={if(@status == :error, do: "alert", else: nil)}
    >
      <h1>{@title} not found</h1>
      <p>No public {@kind} exists at {@record_id}.</p>
      <.link patch={if(@kind == :auction, do: "/autolaunch/auctions", else: "/autolaunch/tokens")}>
        Return to {@title}s
      </.link>
    </section>
    """
  end

  attr :record, :map, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :fields, :map, required: true
  attr :quote, :map, default: nil
  attr :notice, :map, default: nil
  attr :prepared, :map, default: nil
  attr :submission, :map, default: nil
  attr :signing, :boolean, required: true
  attr :positions, :list, required: true

  defp auction_wallet(assigns) do
    ~H"""
    <section
      id="auction-bid-wallet"
      phx-hook="AutolaunchBidWallet"
      aria-labelledby="auction-bid-wallet-title"
    >
      <p class="autolaunch-kicker">Wallet action</p>
      <h2 id="auction-bid-wallet-title">Prepare an auction bid</h2>
      <p>
        Regent prepares the exact approval and auction request. Your verified wallet reviews and
        signs both requests.
      </p>

      <p :if={@account_control.kind == :sign_in} class="autolaunch-empty">
        Sign in to prepare a bid from a verified wallet.
      </p>

      <form
        :if={@account_control.kind == :signed_in}
        id="auction-bid-form"
        phx-change="autolaunch_bid_changed"
        phx-submit="prepare_autolaunch_bid"
      >
        <label>
          <span>Quote-token amount</span>
          <input
            type="text"
            inputmode="decimal"
            name="bid[amount]"
            value={@fields["amount"]}
            autocomplete="off"
            required
          />
        </label>
        <label>
          <span>Maximum price</span>
          <input
            type="text"
            inputmode="decimal"
            name="bid[max_price]"
            value={@fields["max_price"]}
            autocomplete="off"
            required
          />
        </label>
        <button type="submit" disabled={@record.state != :active || not is_nil(@submission)}>
          Review bid
        </button>
      </form>

      <dl :if={@quote} id="auction-bid-quote">
        <div>
          <dt>Estimated tokens</dt><dd>{@quote.estimated_tokens_if_end_now}</dd>
        </div>
        <div>
          <dt>Current clearing price</dt><dd>{@quote.current_clearing_price}</dd>
        </div>
        <div>
          <dt>Position now</dt><dd>{display_action(@quote.status_band)}</dd>
        </div>
      </dl>

      <p
        :if={@notice}
        class={"autolaunch-draft-notice autolaunch-draft-notice--#{@notice.tone}"}
        role={if(@notice.tone == :error, do: "alert", else: "status")}
      >
        {@notice.message}
      </p>

      <section :if={@prepared} id="auction-bid-review" aria-label="Wallet action review">
        <p class="autolaunch-kicker">Review before signing</p>
        <h3>{bid_action_label(@prepared.action)}</h3>
        <p>{@prepared.risk_copy}</p>
        <dl>
          <div :if={@prepared.arguments[:amount]}>
            <dt>Amount</dt><dd>{@prepared.arguments[:amount]}</dd>
          </div>
          <div :if={@prepared.arguments[:max_price]}>
            <dt>Maximum price</dt><dd>{@prepared.arguments[:max_price]}</dd>
          </div>
          <div>
            <dt>Network</dt><dd>Base</dd>
          </div>
          <div>
            <dt>Wallet</dt><dd>{@prepared.expected_signer}</dd>
          </div>
          <div>
            <dt>Contract</dt><dd>{@prepared.to}</dd>
          </div>
          <div>
            <dt>Native value</dt><dd>0 ETH</dd>
          </div>
        </dl>
        <p :if={@prepared.approval}>
          Your wallet first requests an exact quote-token approval for this bid. It is not an
          unlimited allowance.
        </p>
        <button
          :if={is_nil(@submission)}
          type="button"
          phx-click="sign_prepared_autolaunch_bid"
          phx-value-action-id={@prepared.action_id}
          disabled={@signing}
        >
          {if @signing, do: "Waiting for wallet", else: "Confirm in wallet"}
        </button>
        <button
          :if={is_nil(@submission)}
          type="button"
          phx-click="cancel_autolaunch_bid_review"
        >
          Cancel review
        </button>
        <button
          :if={
            @submission && @submission[:approval_transaction_hash] &&
              !@submission[:transaction_hash] && @submission.status == :approval_verified
          }
          type="button"
          phx-click="sign_prepared_autolaunch_bid"
          phx-value-action-id={@prepared.action_id}
          disabled={@signing}
        >
          {if @signing, do: "Waiting for wallet", else: "Continue to bid"}
        </button>
        <button
          :if={
            @submission && @submission[:approval_transaction_hash] &&
              !@submission[:transaction_hash] && @submission.status == :approval_pending
          }
          type="button"
          phx-click="retry_autolaunch_bid_approval_verification"
          disabled={@signing}
        >
          Verify approval
        </button>
        <button
          :if={
            @submission && @submission[:approval_transaction_hash] &&
              !@submission[:transaction_hash]
          }
          type="button"
          phx-click="cancel_autolaunch_bid_approval"
        >
          Cancel bid
        </button>
        <p :if={
          @submission && @submission[:approval_transaction_hash] &&
            !@submission[:transaction_hash]
        }>
          Cancelling does not revoke a confirmed quote-token allowance or stop a pending approval.
        </p>
        <button
          :if={@submission && @submission[:transaction_hash]}
          type="button"
          phx-click="retry_autolaunch_bid_confirmation"
          disabled={@signing}
        >
          Retry confirmation
        </button>
      </section>

      <section :if={@positions != []} id="auction-owned-bids" aria-labelledby="owned-bids-title">
        <h3 id="owned-bids-title">Your bid positions</h3>
        <article :for={position <- @positions} id={"auction-owned-bid-#{position.bid_id}"}>
          <p>{display_status(position.status)} · {position.amount}</p>
          <button
            :if={position.status in ["active", "borderline", "inactive"]}
            type="button"
            phx-click="prepare_autolaunch_bid_position"
            phx-value-action="exit_bid"
            phx-value-bid-id={position.bid_id}
          >
            Review exit
          </button>
          <button
            :if={position.status == "returnable"}
            type="button"
            phx-click="prepare_autolaunch_bid_position"
            phx-value-action="return_quote_token"
            phx-value-bid-id={position.bid_id}
          >
            Review return
          </button>
          <button
            :if={position.status == "claimable"}
            type="button"
            phx-click="prepare_autolaunch_bid_position"
            phx-value-action="claim_bid"
            phx-value-bid-id={position.bid_id}
          >
            Review claim
          </button>
        </article>
      </section>
    </section>
    """
  end

  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :launch_drafts, :list, required: true
  attr :draft_fields, :map, required: true
  attr :draft_notice, :map, default: nil
  attr :regent, :map, default: nil

  defp create(assigns) do
    ~H"""
    <section id="autolaunch-create" class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch · Create</p>
        <h1>Create a launch</h1>
        <p>
          Prepare the launch on the web, then review every bid and money action in your wallet.
        </p>
      </header>

      <section class="autolaunch-reputation" aria-labelledby="autolaunch-reputation-title">
        <div>
          <p class="autolaunch-kicker">Optional reputation</p>
          <h2 id="autolaunch-reputation-title">Strengthen the public signal</h2>
          <p>Connect all four when available. None is required to sign in or create.</p>
        </div>
        <ul>
          <li :for={network <- ["X", "Farcaster", "ENS", "World"]}>
            <span aria-hidden="true">◇</span> Verified {network}
          </li>
        </ul>
      </section>

      <.empty_state
        :if={@account_control.kind == :sign_in}
        copy="Sign in to prepare your launch."
      />

      <div :if={@account_control.kind == :signed_in && is_nil(@regent)} class="autolaunch-empty">
        <p>Form your Regent before creating a launch draft.</p>
        <.link patch="/formation">Open Formation</.link>
      </div>

      <section
        :if={@account_control.kind == :signed_in && @regent}
        class="autolaunch-draft-workspace"
        aria-labelledby="launch-draft-title"
      >
        <div>
          <p class="autolaunch-kicker">Private preparation</p>
          <h2 id="launch-draft-title">Draft the public launch identity</h2>
          <p>
            This saves a private draft for {@regent.display_name}. It does not create an auction,
            publish a token, or request a wallet action.
          </p>
        </div>

        <form id="create-launch-draft" phx-submit="create_launch_draft" class="autolaunch-draft-form">
          <label>
            <span>Launch title</span>
            <input
              type="text"
              name="launch_draft[title]"
              value={@draft_fields["title"]}
              maxlength="160"
              required
            />
          </label>
          <label>
            <span>Token name</span>
            <input
              type="text"
              name="launch_draft[token_name]"
              value={@draft_fields["token_name"]}
              maxlength="100"
              required
            />
          </label>
          <label>
            <span>Token symbol</span>
            <input
              type="text"
              name="launch_draft[symbol]"
              value={@draft_fields["symbol"]}
              maxlength="16"
              pattern="[A-Z0-9]+"
              autocapitalize="characters"
              required
            />
          </label>
          <label>
            <span>Public summary</span>
            <textarea name="launch_draft[summary]" maxlength="2000">{@draft_fields["summary"]}</textarea>
          </label>
          <button type="submit">Save private draft</button>
        </form>

        <p
          :if={@draft_notice}
          class={"autolaunch-draft-notice autolaunch-draft-notice--#{@draft_notice.tone}"}
          role="status"
        >
          {@draft_notice.message}
        </p>

        <div id="launch-drafts" class="autolaunch-drafts">
          <h2>Private drafts</h2>
          <p :if={@launch_drafts == []}>No launch drafts yet.</p>
          <article :for={draft <- @launch_drafts} id={"launch-draft-#{draft.id}"}>
            <p class="autolaunch-kicker">Private draft · {draft.symbol}</p>
            <h3>{draft.title}</h3>
            <form
              id={"revise-launch-draft-#{draft.id}"}
              phx-submit="revise_launch_draft"
              class="autolaunch-draft-form"
            >
              <input type="hidden" name="draft_id" value={draft.id} />
              <label>
                <span>Launch title</span>
                <input
                  type="text"
                  name="launch_draft[title]"
                  value={draft.title}
                  maxlength="160"
                  required
                />
              </label>
              <label>
                <span>Token name</span>
                <input
                  type="text"
                  name="launch_draft[token_name]"
                  value={draft.token_name}
                  maxlength="100"
                  required
                />
              </label>
              <label>
                <span>Token symbol</span>
                <input
                  type="text"
                  name="launch_draft[symbol]"
                  value={draft.symbol}
                  maxlength="16"
                  pattern="[A-Z0-9]+"
                  autocapitalize="characters"
                  required
                />
              </label>
              <label>
                <span>Public summary</span>
                <textarea name="launch_draft[summary]" maxlength="2000">{draft.summary}</textarea>
              </label>
              <button type="submit">Save draft changes</button>
            </form>
          </article>
        </div>
      </section>
    </section>
    """
  end

  attr :copy, :string, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="autolaunch-empty">
      <p>{@copy}</p>
    </div>
    """
  end

  defp record_path(:auction, id), do: "/autolaunch/auctions/#{id}"
  defp record_path(:token, id), do: "/autolaunch/tokens/#{id}"

  defp record_label(:auction, record), do: record.title
  defp record_label(:token, record), do: "#{record.name} · #{record.symbol}"

  defp record_fallback(:auction), do: "No public summary yet."
  defp record_fallback(:token), do: "No public token summary yet."

  defp collection_record_kind(:auctions), do: :auction
  defp collection_record_kind(:tokens), do: :token

  defp subject_label(%{subject_id: subject_id}), do: subject_id

  defp buyback_argument(%{arguments: arguments}, key) do
    Map.get(arguments, key, Map.get(arguments, Atom.to_string(key)))
  end

  defp subject_payment_argument(%{arguments: arguments}, key) do
    Map.get(arguments, key, Map.get(arguments, Atom.to_string(key)))
  end

  defp subject_payment_field(fields, key), do: Map.get(fields, key, "")

  defp subject_payment_locked?(prepared, submission),
    do: not is_nil(prepared) or not is_nil(submission)

  defp subject_payment_title("create_payment_link"), do: "Create payment link"
  defp subject_payment_title("create_canonical_payment_link"), do: "Create canonical payment link"
  defp subject_payment_title("set_payment_link_canonical"), do: "Set canonical status"
  defp subject_payment_title("set_payment_link_receiver_state"), do: "Set receiver state"
  defp subject_payment_title("sweep_usdc"), do: "Sweep ingress USDC"
  defp subject_payment_title("stake"), do: "Stake subject tokens"
  defp subject_payment_title("unstake"), do: "Unstake subject tokens"
  defp subject_payment_title("claim_usdc"), do: "Claim subject USDC"

  defp yes_no(true), do: "Yes"
  defp yes_no(false), do: "No"

  defp launch_label(%{token_name: token_name, token_symbol: token_symbol}),
    do: "#{token_name} · #{token_symbol}"

  defp launch_agent(%{agent_name: value}) when is_binary(value) and value != "", do: value
  defp launch_agent(%{agent_id: value}), do: value

  defp bid_title(%{token: %{name: name, symbol: symbol}}), do: "#{name} · #{symbol}"
  defp bid_title(%{auction: %{title: title}}), do: title
  defp bid_title(%{bid_id: bid_id}), do: "Bid #{bid_id}"

  defp bid_action_label("submit_bid"), do: "Submit bid"
  defp bid_action_label("exit_bid"), do: "Exit bid"
  defp bid_action_label("return_quote_token"), do: "Return quote tokens"
  defp bid_action_label("claim_bid"), do: "Claim launch tokens"

  defp display_status(value) do
    value
    |> display_action()
    |> String.capitalize()
  end

  defp display_text(nil), do: "Not available"
  defp display_text(value) when is_integer(value), do: Integer.to_string(value)

  defp display_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "Not available"
      text -> text
    end
  end

  defp display_bps(nil), do: "Not available"
  defp display_bps(value), do: "#{value} bps"

  defp display_action(value) do
    value
    |> display_text()
    |> String.replace("_", " ")
  end

  defp display_time(%DateTime{} = value),
    do: Calendar.strftime(value, "%b %-d, %Y at %H:%M UTC")

  defp display_time(_value), do: "Not available"

  defp settlement_ready?(%{pending_buyback_usdc_raw: value}) when is_binary(value),
    do: String.trim(value) != ""

  defp settlement_ready?(_record), do: false
end
