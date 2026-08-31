defmodule AshPlatformWeb.AutolaunchLive do
  @moduledoc false
  use Phoenix.Component

  import AshPlatformWeb.Components.CommentLedger
  import AshPlatformWeb.Components.AutolaunchMarketCard
  import AshPlatformWeb.Components.XConnections
  alias AshPlatform.Autolaunch.{Lab, LaunchDraft, Token, TreasurySecurity}

  @address_hint "0x followed by exactly 40 hexadecimal characters."

  @token_detail_fields [
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
      key: :required_regent_raised,
      param: "required_regent_raised",
      label: "Required raise in REGENT",
      kind: :text,
      hint: "Digits only, with at most 18 decimal places."
    }
  ]

  @treasury_field %{
    key: :treasury,
    param: "treasury",
    label: "Immutable treasury recipient",
    kind: :text,
    hint: @address_hint
  }

  @stored_params Enum.map(@token_detail_fields, & &1.param) ++
                   ["image", "treasury", "treasury_path", "eoa_acknowledgement"]

  def token_detail_params, do: Enum.map(@token_detail_fields, & &1.param)
  def treasury_params, do: ["treasury", "treasury_path", "eoa_acknowledgement"]
  def draft_field_params, do: @stored_params

  def blank_draft_fields,
    do:
      @stored_params
      |> Map.new(&{&1, ""})
      |> Map.merge(%{"treasury_path" => "safe", "eoa_acknowledgement" => ""})

  def draft_values(nil), do: blank_draft_fields()

  def draft_values(draft) do
    Map.new(@stored_params, fn param ->
      value = Map.get(draft, String.to_existing_atom(param))

      {param,
       cond do
         is_nil(value) -> ""
         is_atom(value) -> Atom.to_string(value)
         true -> value
       end}
    end)
  end

  attr :route_spec, :map, required: true
  attr :params, :map, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :featured_auctions, :list, required: true
  attr :recent_auctions, :list, required: true
  attr :top_tokens, :list, required: true
  attr :graduated_tokens, :list, required: true
  attr :active_auctions, :list, default: []
  attr :explore_items, :list, default: []
  attr :creator_connections, :map, default: %{}
  attr :search_query, :string, default: ""
  attr :x_connections, :list, default: []
  attr :x_oauth_enabled, :boolean, default: false
  attr :market, :map, default: %{generation: 0, head: nil, degraded?: false, auctions: %{}}
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
  attr :draft_notice, :map, default: nil
  attr :launch_image_upload, :map, default: nil
  attr :status, :atom, required: true
  attr :comments, :list, required: true
  attr :comments_status, :atom, required: true
  attr :comment_notice, :map, default: nil
  attr :comment_request_id, :string, required: true
  attr :comment_draft, :string, required: true
  attr :current_human_id, :integer, default: nil
  attr :comment_admin, :boolean, required: true

  def page(assigns) do
    assigns = assign(assigns, :local_lab?, Lab.enabled?())

    ~H"""
    <p
      :if={@local_lab?}
      id="autolaunch-local-lab-warning"
      class="autolaunch-kicker autolaunch-lab-warning"
      role="status"
    >
      Local Base fork · test assets · no mainnet value
    </p>
    <.overview
      :if={@route_spec.route_id == :autolaunch}
      featured_auctions={@featured_auctions}
      recent_auctions={@recent_auctions}
      top_tokens={@top_tokens}
      graduated_tokens={@graduated_tokens}
      active_auctions={@active_auctions}
      explore_items={@explore_items}
      creator_connections={@creator_connections}
      search_query={@search_query}
      market={@market}
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
      market_snapshot={auction_market_snapshot(@market, @record)}
      creator_connections={connections_for(@record, @creator_connections)}
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
      account_control={@account_control}
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
      draft_notice={@draft_notice}
      launch_image_upload={@launch_image_upload}
      session_lease={@session_lease}
      current_human_id={@current_human_id}
      x_connections={@x_connections}
      x_oauth_enabled={@x_oauth_enabled}
    />
    """
  end

  attr :positions, :list, required: true
  attr :returnable_positions, :list, required: true
  attr :claimed_token_positions, :list, required: true
  attr :status, :atom, required: true
  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true

  defp holdings(assigns) do
    ~H"""
    <section id="autolaunch-holdings" class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Autolaunch · Portfolio</p>
        <h1>Your portfolio</h1>
        <p>Review bid positions and launch tokens connected to your verified wallets.</p>
      </header>

      <p :if={@account_control.kind == :sign_in} class="autolaunch-empty">
        Sign in to view your portfolio.
      </p>

      <p
        :if={@account_control.kind != :sign_in && @status == :error}
        class="autolaunch-empty"
        role="alert"
      >
        Your portfolio is unavailable right now.
      </p>

      <div :if={@account_control.kind != :sign_in && @status == :ready}>
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
      <header class="autolaunch-heading">
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
      <header class="autolaunch-heading">
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
        :if={@record.chain_id != Lab.chain_id()}
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
  attr :active_auctions, :list, required: true
  attr :explore_items, :list, required: true
  attr :creator_connections, :map, required: true
  attr :search_query, :string, required: true
  attr :status, :atom, required: true
  attr :market, :map, required: true

  defp overview(assigns) do
    ~H"""
    <section id="autolaunch-overview" class="autolaunch-page launchpad-home">
      <header class="launchpad-home__topbar">
        <form
          id="autolaunch-market-search"
          class="launchpad-search"
          phx-hook="AutolaunchSearch"
          data-query={@search_query}
          role="search"
        >
          <label for="autolaunch-market-query">Search auctions, tokens, addresses, or creators</label>
          <span aria-hidden="true">⌕</span>
          <input
            id="autolaunch-market-query"
            type="search"
            name="q"
            value={@search_query}
            placeholder="Search Autolaunch"
            autocomplete="off"
          />
          <button :if={@search_query != ""} type="button" data-autolaunch-search-clear>
            Clear
          </button>
        </form>
        <.link patch="/autolaunch/create" class="launchpad-create-link">
          <span aria-hidden="true">＋</span> Create
        </.link>
      </header>

      <p :if={@status == :error} class="autolaunch-inline-error" role="alert">
        Market data is unavailable right now.
      </p>

      <.launchpad_section
        id="launchpad-graduated"
        title="Graduated"
        copy="Tokens whose auctions reached graduation."
        kind={:token}
        records={@graduated_tokens}
        creator_connections={@creator_connections}
        empty_copy={empty_market_copy(@search_query, "No graduated tokens yet.")}
        featured
      />

      <.launchpad_section
        id="launchpad-active"
        title="Active auctions"
        copy="Live raises accepting bids on the local Base fork."
        kind={:auction}
        records={@active_auctions}
        creator_connections={@creator_connections}
        empty_copy={empty_market_copy(@search_query, "No active auctions yet.")}
      />

      <section
        id="launchpad-explore"
        class="launchpad-section"
        aria-labelledby="launchpad-explore-title"
      >
        <header>
          <div>
            <h2 id="launchpad-explore-title">Explore</h2>
            <p>Current auctions and graduated tokens together.</p>
          </div>
          <span>{length(@explore_items)}</span>
        </header>
        <p :if={@explore_items == []} class="launchpad-section__empty">
          {empty_market_copy(@search_query, "Nothing to explore yet.")}
        </p>
        <div :if={@explore_items != []} class="launchpad-card-grid">
          <.autolaunch_market_card
            :for={item <- @explore_items}
            kind={item.kind}
            record={item.record}
            creator_connections={connections_for(item.record, @creator_connections)}
          />
        </div>
      </section>

      <p
        :if={@market.head && !@market.degraded?}
        class="autolaunch-market-freshness"
        role="status"
      >
        Local market current at block {@market.head.number}.
      </p>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :copy, :string, required: true
  attr :kind, :atom, required: true
  attr :records, :list, required: true
  attr :creator_connections, :map, required: true
  attr :empty_copy, :string, required: true
  attr :featured, :boolean, default: false

  defp launchpad_section(assigns) do
    ~H"""
    <section
      id={@id}
      class={["launchpad-section", @featured && "launchpad-section--featured"]}
      aria-labelledby={"#{@id}-title"}
    >
      <header>
        <div>
          <h2 id={"#{@id}-title"}>{@title}</h2>
          <p>{@copy}</p>
        </div>
        <span>{length(@records)}</span>
      </header>
      <p :if={@records == []} class="launchpad-section__empty">{@empty_copy}</p>
      <div :if={@records != []} class="launchpad-card-grid">
        <.autolaunch_market_card
          :for={record <- @records}
          kind={@kind}
          record={record}
          creator_connections={connections_for(record, @creator_connections)}
        />
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :kind, :atom, required: true
  attr :records, :list, required: true
  attr :empty_copy, :string, required: true

  defp market_feed(assigns) do
    ~H"""
    <section class="autolaunch-feed" aria-label={@title}>
      <header>
        <h3>{@title}</h3>
        <span>{length(@records)} shown</span>
      </header>
      <p :if={@records == []} class="autolaunch-feed__empty">{@empty_copy}</p>
      <ol :if={@records != []}>
        <li :for={record <- @records}>
          <.link patch={record_path(@kind, record.id)}>
            <span class="autolaunch-feed__status">{market_status(@kind, record)}</span>
            <strong>{record_label(@kind, record)}</strong>
            <span class="autolaunch-feed__summary">
              {record_summary(@kind, record) || record_fallback(@kind)}
            </span>
            <span class="autolaunch-feed__metric">{market_metric(@kind, record)}</span>
            <span class="autolaunch-feed__action">{market_action(@kind)}
            <span aria-hidden="true">→</span></span>
          </.link>
          <.treasury_security
            :if={!Lab.enabled?()}
            report={report(record)}
            surface={"overview-#{@kind}-#{record.id}"}
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
            do: "Discover live raises, compare auction state, and open one to place a bid.",
            else: "Explore tokens that completed an auction and graduated to liquidity."
          ),
        empty_title: if(assigns.kind == :auctions, do: "No auctions yet", else: "No tokens yet"),
        empty_copy:
          if(
            assigns.kind == :auctions,
            do: "Start the first launch and it will appear here for bidders.",
            else: "Tokens appear here after their auction graduates."
          ),
        empty_action:
          if(assigns.kind == :auctions, do: "Create a launch", else: "Browse auctions"),
        empty_path:
          if(assigns.kind == :auctions,
            do: "/autolaunch/create",
            else: "/autolaunch/auctions"
          )
      )

    ~H"""
    <section id={"autolaunch-#{@kind}"} class="autolaunch-page">
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">Browse the market</p>
        <h1>{@title}</h1>
        <p>{@copy}</p>
      </header>
      <section
        :if={@status == :ready && @records == []}
        class="autolaunch-empty autolaunch-market-empty"
      >
        <p class="autolaunch-kicker">Be first</p>
        <h2>{@empty_title}</h2>
        <p>{@empty_copy}</p>
        <.link patch={@empty_path}>{@empty_action} <span aria-hidden="true">→</span></.link>
      </section>
      <.empty_state :if={@status == :error} copy="Public records are unavailable right now." />
      <.market_feed
        :if={@status == :ready && @records != []}
        title={@title}
        kind={collection_record_kind(@kind)}
        records={@records}
        empty_copy=""
      />
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
  attr :market_snapshot, :map, default: nil
  attr :creator_connections, :map, default: %{}

  defp detail(assigns) do
    assigns =
      assign(assigns,
        title: if(assigns.kind == :auction, do: "Auction", else: "Token"),
        local_lab?: Lab.enabled?()
      )

    ~H"""
    <article
      :if={@status == :ready && @record}
      id={"autolaunch-#{@kind}-detail"}
      class="autolaunch-page"
    >
      <header class="autolaunch-heading">
        <p class="autolaunch-kicker">
          <%= if @local_lab? do %>
            Local Base fork · test assets · no mainnet value
          <% else %>
            Autolaunch · {@title}
          <% end %>
        </p>
        <h1>{record_label(@kind, @record)}</h1>
        <p>{record_summary(@kind, @record) || record_fallback(@kind)}</p>
      </header>
      <.autolaunch_market_card
        kind={@kind}
        record={@record}
        creator_connections={@creator_connections}
        linked={false}
        class="launchpad-card--detail"
      />
      <.treasury_security
        :if={!@local_lab?}
        report={report(@record)}
        surface={"#{@kind}-detail"}
      />
      <dl :if={@local_lab? && @kind == :auction && @market_snapshot} class="autolaunch-live-market">
        <div>
          <dt>Local block</dt><dd>{@market_snapshot.block_number}</dd>
        </div>
        <div>
          <dt>REGENT raised</dt><dd>{@market_snapshot.currency_raised}</dd>
        </div>
        <div>
          <dt>Tokens remaining</dt><dd>{@market_snapshot.remaining_supply}</dd>
        </div>
        <div>
          <dt>Claim block</dt><dd>{@market_snapshot.claim_block}</dd>
        </div>
      </dl>
      <.live_component
        :if={@kind == :auction}
        module={AshPlatformWeb.AutolaunchBidComponent}
        id="autolaunch-bid"
        auction={@record}
        authenticated={@account_control.kind == :signed_in}
        current_human_id={@current_human_id}
        session_lease={@session_lease}
      />
      <.live_component
        :if={@local_lab? && @kind == :auction}
        module={AshPlatformWeb.AutolaunchLabPositionComponent}
        id="autolaunch-lab-position"
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
  attr :draft_notice, :map, default: nil
  attr :launch_image_upload, :map, default: nil
  attr :session_lease, :map, default: nil
  attr :current_human_id, :integer, default: nil
  attr :x_connections, :list, default: []
  attr :x_oauth_enabled, :boolean, default: false

  defp create(assigns) do
    draft = List.first(assigns.launch_drafts)

    assigns =
      assigns
      |> assign(:active_draft, draft)
      |> assign(:token_complete?, draft && LaunchDraft.token_details_complete?(draft))
      |> assign(:treasury_complete?, draft && LaunchDraft.treasury_complete?(draft))
      |> assign(:launch_ready?, draft && LaunchDraft.launch_ready?(draft))
      |> assign(:draft_x_connections, Map.new(assigns.x_connections, &{&1.role, &1}))

    ~H"""
    <section id="autolaunch-create" class="autolaunch-page launchpad-create">
      <header class="launchpad-create__header">
        <p class="autolaunch-kicker">Autolaunch · Create</p>
        <h1>Launch an auction</h1>
        <p>
          Add the public token details, choose the treasury, then review the exact transactions.
          Draft changes save privately to your account. Your wallet remains in control.
        </p>
      </header>

      <.empty_state
        :if={@account_control.kind == :sign_in}
        copy="Sign in to prepare your launch."
      />

      <section
        :if={@account_control.kind == :signed_in}
        class="launchpad-create__workspace"
        aria-labelledby="launch-draft-title"
      >
        <div class="launchpad-create__form-column">
          <form
            id="launch-token-details"
            phx-change="autosave_launch_token_details"
            phx-submit="autosave_launch_token_details"
            class="launchpad-form-section"
          >
            <header>
              <div>
                <p class="autolaunch-kicker">Public identity</p>
                <h2 id="launch-draft-title">Token details</h2>
              </div>
              <span>{stage_status(@token_complete?)}</span>
            </header>

            <div class="launchpad-form-grid">
              <.draft_field
                :for={field <- token_detail_fields()}
                field={field}
                form_id="launch-token-details"
                hint={field.hint}
                value={@draft_values[field.param]}
                error={@draft_errors[field.param]}
                autosave
              />
            </div>

            <div class="autolaunch-draft-field autolaunch-draft-field--wide launchpad-upload">
              <label for="launch-image-upload">Token image</label>
              <p class="autolaunch-draft-hint">
                PNG, JPEG, or WebP · maximum 2 MiB · one permanent image per account.
                <strong>Recommended: 400 × 400 px</strong>
              </p>
              <div class="launchpad-upload__control">
                <img
                  :if={is_binary(@draft_values["image"]) && @draft_values["image"] != ""}
                  class="autolaunch-image-preview"
                  src={@draft_values["image"]}
                  alt="Saved token image"
                />
                <.live_file_input
                  :if={@launch_image_upload}
                  upload={@launch_image_upload}
                  id="launch-image-upload"
                />
              </div>
              <div :for={entry <- (@launch_image_upload && @launch_image_upload.entries) || []}>
                <.live_img_preview entry={entry} class="autolaunch-image-preview" />
                <p>{entry.client_name} · {upload_progress(entry.progress)}</p>
              </div>
              <p
                :for={error <- (@launch_image_upload && upload_errors(@launch_image_upload)) || []}
                class="autolaunch-draft-error"
                role="alert"
              >
                {upload_error(error)}
              </p>
            </div>
          </form>

          <.x_connections
            id="autolaunch-create-x-connections"
            connections={@x_connections}
            enabled={@x_oauth_enabled}
            compact
          />

          <form
            id="launch-treasury-details"
            phx-hook="AutolaunchLaunchDraft"
            phx-change="autosave_launch_treasury"
            phx-submit="autosave_launch_treasury"
            class="launchpad-form-section"
          >
            <header>
              <div>
                <p class="autolaunch-kicker">Proceeds</p>
                <h2>Treasury</h2>
              </div>
              <span>{stage_status(@treasury_complete?)}</span>
            </header>
            <.custody_path
              form_id="launch-treasury-details"
              path={@draft_values["treasury_path"]}
              acknowledgement={@draft_values["eoa_acknowledgement"]}
              error={@draft_errors["eoa_acknowledgement"]}
            />
            <.draft_field
              field={treasury_field()}
              form_id="launch-treasury-details"
              hint={treasury_field().hint}
              value={@draft_values["treasury"]}
              error={@draft_errors["treasury"]}
              autosave
            />
          </form>

          <section id="launch-transactions" class="launchpad-form-section launchpad-transactions">
            <header>
              <div>
                <p class="autolaunch-kicker">Wallet review</p>
                <h2>Launch transactions</h2>
              </div>
              <span>{if @launch_ready?, do: "Ready", else: "Details required"}</span>
            </header>
            <p>
              The wallet component shows the exact REGENT fee and transaction sequence before
              anything is submitted.
            </p>
            <.live_component
              :if={@launch_ready?}
              module={AshPlatformWeb.AutolaunchLaunchWalletComponent}
              id={"autolaunch-launch-wallet-#{@active_draft.id}"}
              draft={@active_draft}
              authenticated
              current_human_id={@current_human_id}
              session_lease={@session_lease}
            />
            <button :if={!@launch_ready?} type="button" disabled>
              Complete token details and treasury
            </button>
          </section>

          <p
            :if={@draft_notice}
            class={"autolaunch-draft-notice autolaunch-draft-notice--#{@draft_notice.tone}"}
            role={notice_role(@draft_notice.tone)}
          >
            {@draft_notice.message}
          </p>
        </div>

        <aside class="launchpad-create__preview" aria-label="Live launch preview">
          <div>
            <p class="autolaunch-kicker">Live preview</p>
            <h2>Your auction</h2>
          </div>
          <.autolaunch_market_card
            kind={:draft}
            record={@draft_values}
            creator_connections={@draft_x_connections}
            preview
          />
          <p>Auctions and graduated tokens use this same public identity.</p>
        </aside>
      </section>
    </section>
    """
  end

  @eoa_acknowledgement "This auction will be owned by my EOA private key, and significant harm and token value will happen if it is lost or compromised. I was warned to create a Gnosis Safe or 0xSplits smart account as the owner, and I realize auction bidders and token owners will see that it is EOA-owned and more risky. I accept these problems, and wish to continue with EOA ownership of the token."

  attr :form_id, :string, required: true
  attr :path, :string, default: "safe"
  attr :acknowledgement, :string, default: ""
  attr :error, :string, default: nil

  defp custody_path(assigns) do
    id = "#{assigns.form_id}-eoa-acknowledgement"

    assigns =
      assign(assigns,
        id: id,
        warning_copy: @eoa_acknowledgement,
        described_by:
          Enum.join(
            ["#{id}-warning", assigns.error && "#{id}-error"] |> Enum.filter(& &1),
            " "
          )
      )

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
      <details>
        <summary>Advanced, high-risk treasury choices</summary>
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
        <label for={@id}>
          To use an EOA, type this warning character-for-character:
        </label>
        <p id={"#{@id}-warning"} class="autolaunch-custody-warning">{@warning_copy}</p>
        <textarea
          id={@id}
          name="launch_draft[eoa_acknowledgement]"
          autocomplete="off"
          aria-invalid={@error && "true"}
          aria-describedby={@described_by}
        >{@acknowledgement}</textarea>
        <p :if={@error} id={"#{@id}-error"} class="autolaunch-draft-error" role="alert">
          {@error}
        </p>
      </details>
    </fieldset>
    """
  end

  attr :field, :map, required: true
  attr :form_id, :string, required: true
  attr :hint, :string, default: nil
  attr :value, :string, default: nil
  attr :error, :string, default: nil
  attr :autosave, :boolean, default: false

  defp draft_field(assigns) do
    id = "#{assigns.form_id}-#{assigns.field.param}"

    assigns =
      assign(assigns, id: id, described_by: described_by(id, assigns.hint, assigns.error))

    ~H"""
    <div class={[
      "autolaunch-draft-field",
      @field.kind == :long_text && "autolaunch-draft-field--wide"
    ]}>
      <label for={@id}>{@field.label}</label>
      <textarea
        :if={@field.kind == :long_text}
        id={@id}
        name={"launch_draft[#{@field.param}]"}
        aria-invalid={@error && "true"}
        aria-describedby={@described_by}
        phx-debounce={@autosave && "400"}
      >{@value}</textarea>
      <input
        :if={@field.kind == :text}
        type="text"
        id={@id}
        name={"launch_draft[#{@field.param}]"}
        value={@value}
        aria-invalid={@error && "true"}
        aria-describedby={@described_by}
        phx-debounce={@autosave && "400"}
      />
      <p :if={@hint} id={"#{@id}-hint"} class="autolaunch-draft-hint">{@hint}</p>
      <p :if={@error} id={"#{@id}-error"} class="autolaunch-draft-error">{@error}</p>
    </div>
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

  defp token_detail_fields, do: @token_detail_fields
  defp treasury_field, do: @treasury_field

  defp stage_status(true), do: "Complete"
  defp stage_status(_incomplete), do: "In progress"

  defp upload_progress(progress), do: "#{progress}%"
  defp upload_error(:too_large), do: "Choose an image no larger than 2 MiB."
  defp upload_error(:not_accepted), do: "Choose a PNG, JPEG, or WebP image."
  defp upload_error(:too_many_files), do: "Choose one image."
  defp upload_error(_error), do: "That image could not be uploaded."

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

  defp record_label(:token, record) do
    presentation = Token.presentation(record)
    "#{presentation.name} · #{presentation.symbol}"
  end

  defp record_summary(:auction, record), do: record.summary
  defp record_summary(:token, record), do: Token.presentation(record).summary

  defp record_fallback(:auction), do: "No public summary yet."
  defp record_fallback(:token), do: "No public token summary yet."

  defp empty_market_copy("", fallback), do: fallback
  defp empty_market_copy(_query, _fallback), do: "No matching auctions or tokens."

  defp connections_for(%{creator_human_account_id: id}, grouped) when is_integer(id),
    do: Map.get(grouped, id, %{})

  defp connections_for(%{auction: %{creator_human_account_id: id}}, grouped)
       when is_integer(id),
       do: Map.get(grouped, id, %{})

  defp connections_for(_record, _grouped), do: %{}

  defp market_status(:auction, record), do: display_status(record.state)
  defp market_status(:token, _record), do: "Graduated"

  defp market_metric(:auction, %{current_clearing_price: price})
       when is_binary(price) and price != "",
       do: "Clearing price #{price}"

  defp market_metric(:auction, _record), do: "Price forming"

  defp market_metric(:token, %{price_quote: price}) when is_binary(price) and price != "",
    do: "Price #{price}"

  defp market_metric(:token, _record), do: "Market price pending"

  defp market_action(:auction), do: "View auction"
  defp market_action(:token), do: "View token"

  defp auction_market_snapshot(%{auctions: auctions}, %{auction_address: address})
       when is_binary(address),
       do: Map.get(auctions, String.downcase(address))

  defp auction_market_snapshot(_market, _record), do: nil

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
  defp display_text(value) when is_atom(value), do: Atom.to_string(value)
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
