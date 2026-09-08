defmodule AshPlatformWeb.AutolaunchLive do
  @moduledoc false
  use Phoenix.Component

  import AshPlatformWeb.Components.CommentLedger
  alias AshPlatform.Autolaunch.TreasurySecurity

  @address_hint "0x followed by exactly 40 hexadecimal characters."

  # The seven fields a founder writes, in the order the page asks for them.
  @draft_fields [
    %{key: :name, param: "name", label: "Name", kind: :text, hint: nil},
    %{key: :symbol, param: "symbol", label: "Symbol", kind: :text, hint: nil},
    %{key: :description, param: "description", label: "Description", kind: :long_text, hint: nil},
    %{
      key: :website,
      param: "website",
      label: "Website",
      kind: :text,
      hint: "A link readers can open."
    },
    %{
      key: :image,
      param: "image",
      label: "Image",
      kind: :text,
      hint: "A link to the picture you want shown."
    },
    %{
      key: :treasury,
      param: "treasury",
      label: "Immutable treasury recipient",
      kind: :text,
      hint: @address_hint
    },
    %{
      key: :required_regent_raised,
      param: "required_regent_raised",
      label: "Required raise in REGENT",
      kind: :text,
      hint: "Digits only, with at most 18 decimal places."
    }
  ]

  def draft_field_params,
    do: Enum.map(@draft_fields, & &1.param) ++ ["treasury_path", "eoa_acknowledgement"]

  def blank_draft_fields,
    do:
      @draft_fields
      |> Map.new(&{&1.param, ""})
      |> Map.merge(%{"treasury_path" => "safe", "eoa_acknowledgement" => ""})

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
  attr :bid_positions, :list, required: true
  attr :returnable_positions, :list, required: true
  attr :claimed_token_positions, :list, required: true
  attr :session_lease, :map, default: nil
  attr :launch_drafts, :list, required: true
  attr :draft_values, :map, required: true
  attr :draft_errors, :map, required: true
  attr :draft_revision, :map, default: nil
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
      session_lease={@session_lease}
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
      session_lease={@session_lease}
      current_human_id={@current_human_id}
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
      draft_values={@draft_values}
      draft_errors={@draft_errors}
      draft_revision={@draft_revision}
      draft_notice={@draft_notice}
      regent={@regent}
      session_lease={@session_lease}
      current_human_id={@current_human_id}
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
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="autolaunch-kicker">Autolaunch · Holdings</p>
        <h1>Your holdings</h1>
        <p>Review bid positions and launch tokens connected to your verified wallets.</p>
      </header>

      <p
        :if={@status == :error}
        class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
        role="alert"
      >
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
          <p :if={@positions == []} class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body">
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
          <p
            :if={@returnable_positions == []}
            class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
          >
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
          <p
            :if={@claimed_token_positions == []}
            class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
          >
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
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
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
          <.treasury_security report={report(launch)} surface={"launch-#{launch.job_id}"} />
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
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="autolaunch-kicker">Autolaunch · Launch</p>
        <h1>{launch_label(@record)}</h1>
        <p>Review this launch's recorded progress, identities, and published addresses.</p>
      </header>

      <.treasury_security report={report(@record)} surface="launch-detail" />

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
        <p
          :if={is_nil(@record.auction_id)}
          class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
        >
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
      class="autolaunch-page autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
    >
      <h1>Launch not found</h1>
      <p>No public launch exists at {@record_id}.</p>
      <.link patch="/autolaunch/launches">Return to Launches</.link>
    </section>

    <section
      :if={@status == :error}
      id="autolaunch-launch-detail"
      class="autolaunch-page autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
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
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
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
          <.treasury_security report={report(subject)} surface={"subject-#{subject.subject_id}"} />
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
  attr :account_control, AshPlatform.AccessContext.AccountControl, default: nil
  attr :session_lease, :map, default: nil
  attr :current_human_id, :integer, default: nil

  defp subject_detail(assigns) do
    ~H"""
    <article
      :if={@status == :ready && @record}
      id="autolaunch-subject-detail"
      class="autolaunch-page"
    >
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="autolaunch-kicker">Autolaunch · Subject</p>
        <h1>{subject_label(@record)}</h1>
        <p>
          Revenue sharing and settlement history for this {display_text(@record.subject_kind)}.
        </p>
      </header>

      <.treasury_security report={report(@record)} surface="subject-detail" />

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

      <%!-- Mounted only for a subject that really loaded, so a not-found or an
            unreadable page never carries a wallet surface at all. --%>
      <.live_component
        module={AshPlatformWeb.AutolaunchSubjectWalletComponent}
        id="autolaunch-subject-wallet"
        subject={@record}
        authenticated={@account_control && @account_control.kind == :signed_in}
        current_human_id={@current_human_id}
        session_lease={@session_lease}
      />

      <section aria-labelledby="subject-revenue-title">
        <h2 id="subject-revenue-title">Revenue</h2>
        <dl>
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
        <p :if={@tokens == []} class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body">
          No related tokens yet.
        </p>
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
        </dl>

        <.subject_action_list
          actions={@settlements}
          empty_copy="No settlements yet."
          id_prefix="subject-settlement"
        />
      </section>
    </article>

    <section
      :if={@status == :empty}
      id="autolaunch-subject-detail"
      class="autolaunch-page autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
    >
      <h1>Subject not found</h1>
      <p>No public subject exists at {@record_id}.</p>
      <.link patch="/autolaunch/subjects">Return to Subjects</.link>
    </section>

    <section
      :if={@status == :error}
      id="autolaunch-subject-detail"
      class="autolaunch-page autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
      role="alert"
    >
      <h1>Subject unavailable</h1>
      <p>This subject could not be loaded right now.</p>
      <.link patch="/autolaunch/subjects">Return to Subjects</.link>
    </section>
    """
  end

  attr :actions, :list, required: true
  attr :empty_copy, :string, required: true
  attr :id_prefix, :string, required: true

  defp subject_action_list(assigns) do
    ~H"""
    <p :if={@actions == []} class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body">
      {@empty_copy}
    </p>
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
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
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
      <p
        :if={@status == :error}
        class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
        role="alert"
      >
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
    <section class="autolaunch-market-section rg-panel rg-panel--surface rg-panel__body">
      <h2>{@title}</h2>
      <p :if={@records == []}>No public records yet.</p>
      <ol :if={@records != []} class="autolaunch-record-list">
        <li :for={record <- @records}>
          <.link patch={record_path(@kind, record.id)}>
            <strong>{record_label(@kind, record)}</strong>
            <span>{record.summary || record_fallback(@kind)}</span>
          </.link>
          <.treasury_security
            report={report(record)}
            surface={"market-#{String.replace(String.downcase(@title), " ", "-")}-#{record.id}"}
          />
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
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
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
          <.treasury_security report={report(record)} surface={"#{@kind}-#{record.id}"} />
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
  attr :session_lease, :map, default: nil
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
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="autolaunch-kicker">Autolaunch · {@title}</p>
        <h1>{record_label(@kind, @record)}</h1>
        <p>{@record.summary || record_fallback(@kind)}</p>
      </header>
      <.treasury_security report={report(@record)} surface={"#{@kind}-detail"} />
      <.live_component
        :if={@kind == :auction}
        module={AshPlatformWeb.AutolaunchBidComponent}
        id="autolaunch-bid"
        auction={@record}
        authenticated={@account_control.kind == :signed_in}
        current_human_id={@current_human_id}
        session_lease={@session_lease}
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
      class="autolaunch-page autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
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

  attr :report, :any, default: nil
  attr :surface, :string, required: true

  defp treasury_security(assigns) do
    assigns = assign(assigns, :view, TreasurySecurity.public_view(assigns.report))

    ~H"""
    <aside id={"treasury-security-#{@surface}"} class="treasury-security" role="status">
      <h3>Treasury security</h3>
      <p :if={is_nil(@view)} class="treasury-security--warning">
        No current treasury report is available. Custody is unverified.
      </p>
      <dl :if={@view}>
        <div>
          <dt>Immutable recipient</dt><dd>{@view.address}</dd>
        </div>
        <div>
          <dt>Type</dt><dd>{display_action(@view.classification)}</dd>
        </div>
        <div>
          <dt>Verification</dt><dd>Awaiting current chain confirmation</dd>
        </div>
        <div :if={@view.downgrade_state != "none"}>
          <dt>Downgrade</dt><dd>Configuration changed after a verified observation</dd>
        </div>
      </dl>
      <p :if={@view} class="treasury-security--warning">
        Verification remains fail-closed until canonical projector refresh is integrated.
      </p>
    </aside>
    """
  end

  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :launch_drafts, :list, required: true
  attr :draft_values, :map, required: true
  attr :draft_errors, :map, required: true
  attr :draft_revision, :map, default: nil
  attr :draft_notice, :map, default: nil
  attr :regent, :map, default: nil
  attr :session_lease, :map, default: nil
  attr :current_human_id, :integer, default: nil

  defp create(assigns) do
    ~H"""
    <section id="autolaunch-create" class="autolaunch-page">
      <header class="autolaunch-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="autolaunch-kicker">Autolaunch · Create</p>
        <h1>Create a launch</h1>
        <p>
          Write the details of the launch you have in mind. Drafts stay private to you, and saving
          one changes nothing outside this page.
        </p>
      </header>

      <.empty_state
        :if={@account_control.kind == :sign_in}
        copy="Sign in to prepare your launch."
      />

      <div
        :if={@account_control.kind == :signed_in && is_nil(@regent)}
        class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body"
      >
        <p>Form your Regent before creating a launch draft.</p>
        <.link patch="/formation">Open Formation</.link>
      </div>

      <section
        :if={@account_control.kind == :signed_in && @regent}
        class="autolaunch-draft-workspace rg-panel rg-panel--surface rg-panel__body"
        aria-labelledby="launch-draft-title"
      >
        <div>
          <p class="autolaunch-kicker">Private preparation</p>
          <h2 id="launch-draft-title">Launch details</h2>
          <p>Saved for {@regent.display_name}. Nothing here is published and no money moves.</p>
        </div>

        <%!-- The browser default reads these two: a refused save owns every
              address it echoes back, and a saved draft starts the next one. --%>
        <form
          id="create-launch-draft"
          phx-hook="AutolaunchLaunchDraft"
          phx-submit="create_launch_draft"
          class="autolaunch-draft-form"
          data-draft-errors={@draft_errors != %{} && "true"}
          data-saved-drafts={length(@launch_drafts)}
        >
          <.custody_path
            form_id="create-launch-draft"
            path={@draft_values["treasury_path"]}
            acknowledgement={@draft_values["eoa_acknowledgement"]}
          />
          <.draft_field
            :for={field <- draft_fields()}
            field={field}
            form_id="create-launch-draft"
            hint={create_hint(field)}
            value={@draft_values[field.param]}
            error={@draft_errors[field.param]}
          />
          <Regent.Primitives.button type="submit">Save draft</Regent.Primitives.button>
        </form>

        <p
          :if={@draft_notice}
          class={"autolaunch-draft-notice autolaunch-draft-notice--#{@draft_notice.tone}"}
          role={notice_role(@draft_notice.tone)}
        >
          {@draft_notice.message}
        </p>

        <div id="launch-drafts" class="autolaunch-drafts">
          <h2>Saved drafts</h2>
          <p :if={@launch_drafts == []}>No drafts yet.</p>
          <article :for={draft <- @launch_drafts} id={"launch-draft-#{draft.id}"}>
            <p class="autolaunch-kicker">Private draft</p>
            <h3>{draft.name}</h3>
            <dl class="autolaunch-draft-review">
              <div :for={field <- review_fields()}>
                <dt>{field.label}</dt>
                <dd>{draft_text(Map.fetch!(draft, field.key))}</dd>
              </div>
            </dl>
            <form
              id={"revise-launch-draft-#{draft.id}"}
              phx-submit="revise_launch_draft"
              class="autolaunch-draft-form"
            >
              <input type="hidden" name="draft_id" value={draft.id} />
              <.custody_path
                form_id={"revise-launch-draft-#{draft.id}"}
                path={revision_extra(@draft_revision, draft, "treasury_path")}
                acknowledgement={revision_extra(@draft_revision, draft, "eoa_acknowledgement")}
              />
              <.draft_field
                :for={field <- draft_fields()}
                field={field}
                form_id={"revise-launch-draft-#{draft.id}"}
                hint={field.hint}
                value={revision_value(@draft_revision, draft, field)}
                error={revision_error(@draft_revision, draft, field)}
              />
              <Regent.Primitives.button type="submit">Save changes</Regent.Primitives.button>
            </form>

            <%!-- Mounted on the draft it launches, so a card that is not saved
                  yet carries no wallet surface at all. --%>
            <.live_component
              module={AshPlatformWeb.AutolaunchLaunchWalletComponent}
              id={"autolaunch-launch-wallet-#{draft.id}"}
              draft={draft}
              authenticated={@account_control.kind == :signed_in}
              current_human_id={@current_human_id}
              session_lease={@session_lease}
            />
          </article>
        </div>
      </section>
    </section>
    """
  end

  @eoa_acknowledgement "This auction will be owned by my EOA private key, and significant harm and token value will happen if it is lost or compromised. I was warned to create a Gnosis Safe or 0xSplits smart account as the owner, and I realize auction bidders and token owners will see that it is EOA-owned and more risky. I accept these problems, and wish to continue with EOA ownership of the token."

  attr :form_id, :string, required: true
  attr :path, :string, default: "safe"
  attr :acknowledgement, :string, default: ""

  defp custody_path(assigns) do
    assigns = assign(assigns, :warning_copy, @eoa_acknowledgement)

    ~H"""
    <fieldset class="autolaunch-custody-path">
      <legend>Choose treasury custody</legend>
      <strong>Create a 2-of-3 Safe on Base</strong>
      <a
        href="https://app.safe.global/new-safe/create?chain=base"
        target="_blank"
        rel="noopener noreferrer"
      >
        Open the official Safe creation flow
      </a>
      <p>Return here and verify the deployed address before launch.</p>
      <label>
        <input
          type="radio"
          name="launch_draft[treasury_path]"
          value="safe"
          checked={@path in [nil, "", "safe", :safe]}
        />
        <span>Use existing Safe</span>
      </label>
      <Regent.Primitives.disclosure
        summary="Advanced, high-risk treasury choices"
        id={"#{@form_id}-custody-details"}
      >
        <label>
          <input
            type="radio"
            name="launch_draft[treasury_path]"
            value="contract"
            checked={@path in ["contract", :contract]}
          /> Existing contract or distribution destination — never verified
        </label>
        <label>
          <input
            type="radio"
            name="launch_draft[treasury_path]"
            value="eoa"
            checked={@path in ["eoa", :eoa]}
          /> Single-key EOA — never verified
        </label>
        <label for={"#{@form_id}-eoa-acknowledgement"}>
          To use an EOA, type this warning character-for-character:
        </label>
        <p class="autolaunch-custody-warning">{@warning_copy}</p>
        <textarea
          id={"#{@form_id}-eoa-acknowledgement"}
          name="launch_draft[eoa_acknowledgement]"
          autocomplete="off"
        >{@acknowledgement}</textarea>
      </Regent.Primitives.disclosure>
    </fieldset>
    """
  end

  attr :field, :map, required: true
  attr :form_id, :string, required: true
  attr :hint, :string, default: nil
  attr :value, :string, default: nil
  attr :error, :string, default: nil

  defp draft_field(assigns) do
    id = "#{assigns.form_id}-#{assigns.field.param}"

    assigns =
      assign(assigns, id: id, described_by: described_by(id, assigns.hint, assigns.error))

    ~H"""
    <Regent.Primitives.field
      id={@id}
      label={@field.label}
      class={[
        "autolaunch-draft-field",
        @field.kind == :long_text && "autolaunch-draft-field--wide"
      ]}
    >
      <textarea
        :if={@field.kind == :long_text}
        id={@id}
        name={"launch_draft[#{@field.param}]"}
        aria-invalid={@error && "true"}
        aria-describedby={@described_by}
        required
      >{@value}</textarea>
      <input
        :if={@field.kind == :text}
        type="text"
        id={@id}
        name={"launch_draft[#{@field.param}]"}
        value={@value}
        aria-invalid={@error && "true"}
        aria-describedby={@described_by}
        required
      />
      <p :if={@hint} id={"#{@id}-hint"} class="autolaunch-draft-hint">{@hint}</p>
      <p :if={@error} id={"#{@id}-error"} class="autolaunch-draft-error">{@error}</p>
    </Regent.Primitives.field>
    """
  end

  attr :copy, :string, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="autolaunch-empty rg-panel rg-panel--surface rg-panel__body">
      <p>{@copy}</p>
    </div>
    """
  end

  defp draft_fields, do: @draft_fields

  defp create_hint(%{hint: hint}), do: hint

  # The card heading already carries the name.
  defp review_fields, do: Enum.reject(@draft_fields, &(&1.key == :name))

  defp draft_text(nil), do: "Not written yet"
  defp draft_text(value), do: value

  # A failed revision belongs to exactly one card; every other card keeps
  # showing what is stored.
  defp revision_value(%{id: id, values: values}, %{id: id}, field), do: values[field.param]
  defp revision_value(_revision, draft, field), do: Map.fetch!(draft, field.key)

  defp revision_error(%{id: id, errors: errors}, %{id: id}, field), do: errors[field.param]
  defp revision_error(_revision, _draft, _field), do: nil

  defp revision_extra(%{id: id, values: values}, %{id: id}, key), do: values[key] || ""
  defp revision_extra(_revision, draft, "treasury_path"), do: draft.treasury_path
  defp revision_extra(_revision, _draft, "eoa_acknowledgement"), do: ""

  defp described_by(id, hint, error) do
    case Enum.filter([hint && "#{id}-hint", error && "#{id}-error"], &is_binary/1) do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  defp notice_role(:error), do: "alert"
  defp notice_role(_tone), do: "status"

  defp record_path(:auction, id), do: "/autolaunch/auctions/#{id}"
  defp record_path(:token, id), do: "/autolaunch/tokens/#{id}"

  defp record_label(:auction, record), do: record.title
  defp record_label(:token, record), do: "#{record.name} · #{record.symbol}"

  defp record_fallback(:auction), do: "No public summary yet."
  defp record_fallback(:token), do: "No public token summary yet."

  defp collection_record_kind(:auctions), do: :auction
  defp collection_record_kind(:tokens), do: :token

  defp report(%{treasury_security_report: %Ash.NotLoaded{}}), do: nil
  defp report(%{treasury_security_report: report}), do: report
  defp report(_record), do: nil

  defp subject_label(%{subject_id: subject_id}), do: subject_id

  defp launch_label(%{token_name: token_name, token_symbol: token_symbol}),
    do: "#{token_name} · #{token_symbol}"

  defp launch_agent(%{agent_name: value}) when is_binary(value) and value != "", do: value
  defp launch_agent(%{agent_id: value}), do: value

  defp bid_title(%{token: %{name: name, symbol: symbol}}), do: "#{name} · #{symbol}"
  defp bid_title(%{auction: %{title: title}}), do: title
  defp bid_title(%{bid_id: bid_id}), do: "Bid #{bid_id}"

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
end
