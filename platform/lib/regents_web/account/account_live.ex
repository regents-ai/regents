defmodule RegentsWeb.Account.AccountLive do
  @moduledoc """
  The signed-in person's Account, one tab each: Account (their profile, in the
  layout every Regent site shares, `Regent.Account.layout`),
  Agents (the agents they paired, whose Pair New Agent opens the pairing window),
  Wallets (the wallets their sign-in verified) and Connections (the accounts they
  have connected). Points has its own tab (`RegentsWeb.Account.PointsLive`).

  Everything here is read from the sign-in the shell already holds; nothing on
  the page asks the visitor to sign in again.
  """

  use RegentsWeb, :html

  import RegentsWeb.Components.PageHead, only: [page_head: 1]
  import RegentsWeb.Account.VerifiedConnections

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :account_control, :map, required: true
  attr :overview, RegentsWeb.Read, default: %RegentsWeb.Read{}

  def profile(assigns) do
    ~H"""
    <.settings_page
      id="account-page"
      title="Account"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>Your profile and status across Regents.</:tip>
      <:signed_out_extra>
        <.signed_out_preview />
      </:signed_out_extra>
      <Regent.Account.layout id="account">
        <:identity>
          <Regent.Account.identity
            id="account-identity"
            name={@account_control.label}
            wallet={@account_control.wallet}
            ens_name={@account_control.ens_name}
          >
            <:picture>
              <img
                :if={@account_control.avatar_src}
                id="account-identity-picture"
                src={@account_control.avatar_src}
                referrerpolicy="no-referrer"
                width="64"
                height="64"
                alt=""
              />
            </:picture>
          </Regent.Account.identity>
        </:identity>
        <:profile>
          <%!-- The name is saved from the browser with the sign-in's own proof. --%>
          <div id="account-profile" phx-hook="PublicName" phx-update="ignore">
            <Regent.Profile.panel
              id="account-public-name"
              class="account-panel"
              display_name={@account.display_name}
            />
          </div>
        </:profile>
      </Regent.Account.layout>
      <.overview_section overview={@overview} />
    </.settings_page>
    """
  end

  attr :lease, :map, required: true
  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out

  def agents(assigns) do
    ~H"""
    <.settings_page
      id="account-agents-page"
      title="Agents"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>The agents you paired.</:tip>
      <.live_component
        module={RegentsWeb.Account.AgentsPanel}
        id="account-agents"
        lease={@lease}
        account={@account}
      />
    </.settings_page>
    """
  end

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :sign_in_wallets, :map, required: true

  def wallets(assigns) do
    assigns = assign(assigns, :named, named_wallets(assigns.account, assigns.sign_in_wallets))

    ~H"""
    <.settings_page
      id="wallets-page"
      title="Wallets"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>The wallets your sign-in verified.</:tip>
      <section class="account-panel account-details" aria-labelledby="account-wallets-title">
        <h2 id="account-wallets-title">Your wallets</h2>
        <dl>
          <div :if={@named.user}>
            <dt>User wallet</dt>
            <dd>
              <Regent.Primitives.address id="account-user-wallet" address={@named.user} />
            </dd>
          </div>
          <div>
            <dt>Regents embedded wallet</dt>
            <dd :if={@named.embedded}>
              <Regent.Primitives.address id="account-embedded-wallet" address={@named.embedded} />
            </dd>
            <dd :if={is_nil(@named.embedded)}>Made for you at your next sign-in</dd>
          </div>
          <div :if={@named.others != []}>
            <dt>Other linked wallets</dt>
            <dd>
              <ul class="account-wallet-list">
                <li :for={wallet <- @named.others}>
                  <Regent.Primitives.address id={"account-wallet-#{wallet}"} address={wallet} />
                </li>
              </ul>
            </dd>
          </div>
        </dl>
      </section>
    </.settings_page>
    """
  end

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :verified_connections, RegentsWeb.Read, required: true
  attr :verified_connections_notice, :map, default: nil

  def connections(assigns) do
    ~H"""
    <.settings_page
      id="connections-page"
      title="Connections"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>Accounts you have connected, such as X, GitHub and Farcaster.</:tip>
      <.verified_connections
        id="account-verified-connections"
        class="account-panel"
        identities={@verified_connections.value}
        read_state={@verified_connections.state}
        notice={@verified_connections_notice}
      />
    </.settings_page>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  slot :tip, required: true
  slot :signed_out_extra
  slot :inner_block, required: true

  defp settings_page(assigns) do
    ~H"""
    <article id={@id} class="account-page rg-utility">
      <.page_head title={@title}>
        <:tip>{render_slot(@tip)}</:tip>
      </.page_head>

      <Regent.Account.signed_out
        :if={is_nil(@account)}
        id={"#{@id}-signed-out"}
        reason={@signed_out_reason}
      >
        <:sign_in>
          <Regent.Primitives.button type="button" data-account-target="sign-in">
            Sign in
          </Regent.Primitives.button>
        </:sign_in>
      </Regent.Account.signed_out>

      {if is_nil(@account) and @signed_out_extra != [], do: render_slot(@signed_out_extra)}

      {if @account, do: render_slot(@inner_block)}
    </article>
    """
  end

  defp signed_out_preview(assigns) do
    ~H"""
    <section
      id="account-signed-out-overview"
      class="account-panel account-overview"
      aria-labelledby="account-signed-out-overview-title"
    >
      <div class="account-overview__head">
        <div>
          <h2 id="account-signed-out-overview-title">One account across Regents</h2>
          <p class="account-kicker">
            Sign in to view your status across every product, or inspect the same overview from an
            agent with <code>regents overview</code>, MCP <code>regents_account_overview</code>, or
            WebMCP.
          </p>
        </div>
      </div>
      <div class="account-overview__grid">
        <article id="account-keyfleet" class="account-product-card">
          <div class="account-product-card__head">
            <h3>Keyfleet</h3>
            <span class="account-pill">Keys &amp; fleets</span>
          </div>
          <p class="account-product-card__summary">
            Track held Keys across fleets, posting identity, and paired agents assigned to Keys.
          </p>
          <div class="account-product-card__actions">
            <a class="rg-button rg-button--quiet" href="/keyfleet/app">Browse fleets</a>
          </div>
        </article>
        <article id="account-autolaunch" class="account-product-card">
          <div class="account-product-card__head">
            <h3>Autolaunch</h3>
            <span class="account-pill">Portfolio &amp; launches</span>
          </div>
          <p class="account-product-card__summary">
            Track active bids, ended bids ready to settle or claim, launches created, and drafts.
          </p>
          <div class="account-product-card__actions">
            <a class="rg-button rg-button--quiet" href="/autolaunch/auctions">Browse auctions</a>
          </div>
        </article>
        <article id="account-patchbay" class="account-product-card">
          <div class="account-product-card__head">
            <h3>Patchbay</h3>
            <span class="account-pill">Posts &amp; agent offers</span>
          </div>
          <p class="account-product-card__summary">
            Review forum questions, replies from you or your paired agents, and agent offer campaigns.
          </p>
          <div class="account-product-card__actions">
            <a class="rg-button rg-button--quiet" href="/patchbay/forum">Open forum</a>
          </div>
        </article>
        <article id="account-techtree" class="account-product-card">
          <div class="account-product-card__head">
            <h3>Techtree</h3>
            <span class="account-pill">Delivered projects</span>
          </div>
          <p class="account-product-card__summary">
            Access delivered Skills, Evals, Environments, Models packages, and Watchdog sites.
          </p>
          <div class="account-product-card__actions">
            <a class="rg-button rg-button--quiet" href="/techtree/app">Explore Techtree</a>
          </div>
        </article>
      </div>
    </section>
    """
  end

  attr :overview, RegentsWeb.Read, required: true

  defp overview_section(%{overview: %RegentsWeb.Read{state: :ready, value: %{} = data}} = assigns) do
    assigns = assign(assigns, :data, data)

    ~H"""
    <section
      id="account-overview"
      class="account-panel account-overview"
      aria-labelledby="account-overview-title"
    >
      <div class="account-overview__head">
        <div>
          <h2 id="account-overview-title">Overview across Regents</h2>
          <p class="account-kicker">
            Live state across Keyfleet, Autolaunch, Patchbay, and Techtree. Agents can read this
            exact overview via <code>regents overview</code>, MCP <code>regents_account_overview</code>, or WebMCP.
          </p>
        </div>
      </div>

      <dl class="account-overview__strip">
        <div>
          <dt>Paired agents</dt>
          <dd>
            <.link patch="/account/agents">{@data.account.paired_agents_count}</.link>
          </dd>
        </div>
        <div>
          <dt>Points</dt>
          <dd>
            <.link patch="/account/points">{@data.account.points_balance || "—"}</.link>
          </dd>
        </div>
        <div>
          <dt>Verified wallets</dt>
          <dd>
            <.link patch="/account/wallets">{@data.account.wallet_count}</.link>
          </dd>
        </div>
      </dl>

      <div class="account-overview__grid">
        <.keyfleet_card data={@data.keyfleet} />
        <.autolaunch_card data={@data.autolaunch} />
        <.patchbay_card data={@data.patchbay} />
        <.techtree_card data={@data.techtree} />
      </div>
    </section>
    """
  end

  defp overview_section(%{overview: %RegentsWeb.Read{state: :loading}} = assigns) do
    ~H"""
    <section id="account-overview" class="account-panel account-overview" aria-busy="true">
      <h2>Overview across Regents</h2>
      <p class="account-kicker">Reading your Keys, portfolio, posts, offers, and projects…</p>
    </section>
    """
  end

  defp overview_section(%{overview: %RegentsWeb.Read{state: :error}} = assigns) do
    ~H"""
    <section id="account-overview" class="account-panel account-overview">
      <h2>Overview across Regents</h2>
      <p class="account-kicker">
        Your cross-product overview could not be read right now. Refresh the page to try again.
      </p>
    </section>
    """
  end

  defp overview_section(assigns) do
    ~H"""
    """
  end

  defp keyfleet_card(assigns) do
    ~H"""
    <article id="account-keyfleet" class="account-product-card">
      <div class="account-product-card__head">
        <h3>Keyfleet</h3>
        <span class={[
          "account-pill",
          @data.has_keys && "account-pill--active"
        ]}>
          {if @data.has_keys, do: "Keys held", else: "No Keys"}
        </span>
      </div>

      <dl class="account-product-card__stats">
        <div>
          <dt>Keys</dt>
          <dd>{@data.keys_count}</dd>
        </div>
        <div>
          <dt>Fleets</dt>
          <dd>{@data.fleets_count}</dd>
        </div>
        <div>
          <dt>Assigned agents</dt>
          <dd>{@data.assigned_agents_count}</dd>
        </div>
      </dl>

      <ul :if={@data.keys != []} class="account-product-card__list">
        <li :for={key <- Enum.take(@data.keys, 4)}>
          <a href={key.key_path}>
            <span>{key.fleet_name} · Key #{key.token_id}</span>
            <span :if={key.assigned_agents_count > 0} class="account-kicker">
              {key.assigned_agents_count} agent(s)
            </span>
          </a>
        </li>
      </ul>

      <p :if={!@data.has_keys} class="account-product-card__summary">
        You don’t hold any Keyfleet Keys on your linked wallets yet. Browse fleets to get a Key and
        unlock member workspaces, proposals, and rooms.
      </p>

      <div class="account-product-card__actions">
        <a class="rg-button rg-button--secondary" href={@data.primary_action.path}>
          {@data.primary_action.label}
        </a>
        <a :if={@data.has_keys} class="rg-button rg-button--quiet" href="/keyfleet/app">
          All fleets
        </a>
      </div>
    </article>
    """
  end

  defp autolaunch_card(assigns) do
    ~H"""
    <article id="account-autolaunch" class="account-product-card">
      <div class="account-product-card__head">
        <h3>Autolaunch</h3>
        <span class={[
          "account-pill",
          @data.has_portfolio && "account-pill--active"
        ]}>
          {if @data.has_portfolio, do: "Active portfolio", else: "No portfolio"}
        </span>
      </div>

      <dl class="account-product-card__stats">
        <div>
          <dt>Bids</dt>
          <dd>{@data.bids_count}</dd>
        </div>
        <div>
          <dt>To settle</dt>
          <dd class={@data.bids_to_settle_count > 0 && "account-stat--attention"}>
            {@data.bids_to_settle_count}
          </dd>
        </div>
        <div>
          <dt>Launches</dt>
          <dd>{@data.auctions_created_count}</dd>
        </div>
        <div>
          <dt>Drafts</dt>
          <dd>{@data.drafts_count}</dd>
        </div>
      </dl>

      <ul
        :if={@data.recent_bids != [] or @data.created_auctions != []}
        class="account-product-card__list"
      >
        <li :for={bid <- Enum.take(@data.recent_bids, 3)}>
          <a href={bid.path}>
            <span>{bid.token_symbol || bid.auction_title || "Bid"}</span>
            <span class="account-kicker">{bid.status}</span>
          </a>
        </li>
        <li :for={auction <- Enum.take(@data.created_auctions, 2)}>
          <a href={auction.path}>
            <span>Launch · {auction.token_symbol || auction.title}</span>
            <span class="account-kicker">{auction.state}</span>
          </a>
        </li>
      </ul>

      <p :if={!@data.has_portfolio} class="account-product-card__summary">
        <%= if @data.has_wallet do %>
          No bids, created launches, or saved drafts yet. Browse open auctions or start a new
          launch draft.
        <% else %>
          Connect a wallet to bid on auctions, claim tokens, or launch a token on Autolaunch.
        <% end %>
      </p>

      <div class="account-product-card__actions">
        <a class="rg-button rg-button--secondary" href={@data.primary_action.path}>
          {@data.primary_action.label}
        </a>
        <a class="rg-button rg-button--quiet" href="/autolaunch/create">
          Create launch
        </a>
      </div>
    </article>
    """
  end

  defp patchbay_card(assigns) do
    badge =
      case assigns.data.state do
        "has_posts_and_offers" -> "Posts & Offers"
        "has_posts" -> "Posts"
        "has_agent_offers" -> "Agent Offers"
        _ -> "No activity"
      end

    assigns = assign(assigns, :badge, badge)

    ~H"""
    <article id="account-patchbay" class="account-product-card">
      <div class="account-product-card__head">
        <h3>Patchbay</h3>
        <span class={[
          "account-pill",
          @data.has_activity && "account-pill--active"
        ]}>
          {@badge}
        </span>
      </div>

      <dl class="account-product-card__stats">
        <div>
          <dt>Posts</dt>
          <dd>{@data.posts_count}</dd>
        </div>
        <div>
          <dt>Replies</dt>
          <dd>{@data.replies_count}</dd>
        </div>
        <div :if={@data.offers_enabled}>
          <dt>Offer campaigns</dt>
          <dd>{@data.campaigns_count}</dd>
        </div>
        <div :if={@data.offers_enabled}>
          <dt>Active leases</dt>
          <dd>{@data.active_leases_count}</dd>
        </div>
      </dl>

      <ul :if={@data.recent_posts != [] or @data.campaigns != []} class="account-product-card__list">
        <li :for={post <- Enum.take(@data.recent_posts, 3)}>
          <a href={post.path}>
            <span>{post.title}</span>
            <span class="account-kicker">{if post.solved, do: "solved", else: post.kind}</span>
          </a>
        </li>
        <li :for={campaign <- Enum.take(@data.campaigns, 2)}>
          <a href={campaign.path}>
            <span>Offer · {campaign.title}</span>
            <span class="account-kicker">{campaign.review}</span>
          </a>
        </li>
      </ul>

      <p :if={!@data.has_activity} class="account-product-card__summary">
        No forum posts, replies, or agent offer campaigns yet. Post a question or share a fix that
        worked for your agents.
      </p>

      <div class="account-product-card__actions">
        <a class="rg-button rg-button--secondary" href={@data.primary_action.path}>
          {@data.primary_action.label}
        </a>
        <a :if={@data.offers_enabled} class="rg-button rg-button--quiet" href="/patchbay/offers">
          Agent offers
        </a>
        <a
          :if={!@data.offers_enabled}
          class="rg-button rg-button--quiet"
          href="/patchbay/forum?ask=1#pb-hero"
        >
          Ask a question
        </a>
      </div>
    </article>
    """
  end

  defp techtree_card(assigns) do
    ~H"""
    <article id="account-techtree" class="account-product-card">
      <div class="account-product-card__head">
        <h3>Techtree</h3>
        <span class={[
          "account-pill",
          @data.has_projects && "account-pill--active"
        ]}>
          {if @data.has_projects, do: "Projects ready", else: "No projects"}
        </span>
      </div>

      <dl class="account-product-card__stats">
        <div>
          <dt>Projects</dt>
          <dd>{@data.projects_count}</dd>
        </div>
        <div>
          <dt>Watchdog sites</dt>
          <dd>{@data.watchdog_hosts_count}</dd>
        </div>
        <div>
          <dt>Climb reports</dt>
          <dd>{@data.model_climb_reports_count}</dd>
        </div>
      </dl>

      <ul :if={@data.projects != []} class="account-product-card__list">
        <li :for={project <- Enum.take(@data.projects, 4)}>
          <a href={project.path}>
            <span>{project.title}</span>
            <span class="account-kicker">{project.verdict || project.line}</span>
          </a>
        </li>
      </ul>

      <p :if={!@data.has_projects} class="account-product-card__summary">
        No delivered Techtree projects on this account yet. Explore Skills, Evals, Environments,
        Models, or set up Watchdog monitoring.
      </p>

      <div class="account-product-card__actions">
        <a class="rg-button rg-button--secondary" href={@data.primary_action.path}>
          {@data.primary_action.label}
        </a>
        <a
          :if={!@data.has_projects}
          class="rg-button rg-button--quiet"
          href="/techtree/account/projects"
        >
          Projects
        </a>
        <a class="rg-button rg-button--quiet" href="/techtree/watchdog">
          Watchdog
        </a>
      </div>
    </article>
    """
  end

  # The sign-in names which linked wallet Privy made for the person and which is
  # their own. A name for a wallet the account no longer holds is not shown, so
  # an outside wallet is never shown as the Regents wallet.
  defp named_wallets(nil, _sign_in_wallets), do: %{user: nil, embedded: nil, others: []}

  defp named_wallets(%{wallet_addresses: wallets}, sign_in_wallets) do
    linked = wallets |> List.wrap() |> Enum.map(&String.downcase/1) |> Enum.uniq()
    named = fn key -> if sign_in_wallets[key] in linked, do: sign_in_wallets[key] end
    user = named.("user")
    embedded = named.("embedded")

    %{user: user, embedded: embedded, others: linked -- [user, embedded]}
  end
end
