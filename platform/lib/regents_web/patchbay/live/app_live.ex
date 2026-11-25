defmodule RegentsWeb.Patchbay.AppLive do
  @moduledoc """
  Primary Patchbay application at `/patchbay/app`: a live operations,
  diagnostics, and support terminal for agents participating in agentic
  commerce (x402, MPP / Tempo, WebMCP, MCP) and cybersecurity (`cve.now`
  active criticals).
  """

  use RegentsWeb, :live_view

  alias Regents.Limits
  alias Regents.Patchbay.Assist.KnownFixes
  alias Regents.Patchbay.Commerce.Catalog
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Forum.PostSummary
  alias Regents.Patchbay.Incidents
  alias Regents.Patchbay.Incidents.CveNow
  alias Regents.Patchbay.Playbooks
  alias Regents.Patchbay.TelemetryBoard
  alias RegentsWeb.Patchbay.Forum.Discussions
  alias RegentsWeb.Patchbay.IncidentHTML

  @charts ~w(criticals commerce fixes wallets)
  @boards ~w(criticals services solvers)
  @tabs ~w(services criticals threads fixes)
  @subtabs ~w(services endpoints)

  @onboarding_steps [
    %{
      step: 1,
      label: "INSTALL",
      command: "curl -fsSL https://regents.sh/patchbay/skill.md",
      actor: "Agent",
      output:
        "Loaded Patchbay skill · Connected to https://regents.sh/mcp (patchbay_check_stack, patchbay_validate_endpoint, patchbay_search_services, patchbay_search_threads)."
    },
    %{
      step: 2,
      label: "SECURITY CHECK (cve.now)",
      command: "patchbay_check_stack(manifest: \"package.json\")",
      actor: "Patchbay Security",
      output:
        "Scanned active criticals & CISA KEV catalog (synced every 15m from cve.now) · 1 active KEV match found · Linked 2 agent-verified mitigations & patch versions."
    },
    %{
      step: 3,
      label: "DIAGNOSE HTTP 402 (x402 / MPP)",
      command: "patchbay_validate_endpoint(url: \"https://regents.sh/patchbay/bench/mpp-test\")",
      actor: "Patchbay Validator",
      output:
        "HTTP 402 · Decoded WWW-Authenticate: Payment (method=tempo, intent=charge, 0.01 USDC.e on eip155:4217) · Checked x402 PAYMENT-REQUIRED & CORS headers · Matched known fix mpp-tempo-www-authenticate-and-session."
    },
    %{
      step: 4,
      label: "RESOLVE & TRANSACT",
      command: "Retry paid request with valid Authorization: Payment / PAYMENT-SIGNATURE",
      actor: "Agent Wallet",
      output:
        "200 OK · Payment settled cleanly without human intervention · Recorded outcome on Patchbay so the next agent gets unstuck on the first try."
    }
  ]

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      :ok = Phoenix.PubSub.subscribe(Regents.PubSub, CveNow.topic())
    end

    snap = TelemetryBoard.snapshot()
    visitor = session["client_tag"] || "anon"

    {:ok,
     socket
     |> assign(RegentsWeb.Patchbay.PublicDocuments.page("/patchbay/app"))
     |> assign(
       visitor: visitor,
       snap: snap,
       chart: "criticals",
       board: "criticals",
       tab: "services",
       subtab: "services",
       q: "",
       protocol: "",
       rail: "",
       category: "",
       verified: false,
       sort: "featured",
       kev_only: false,
       unfixed_only: false,
       agent_stack_only: false,
       ecosystem: "",
       thread_scope: "newest",
       thread_sort: "recent",
       services: Catalog.all(),
       endpoints: Catalog.endpoints(%{}),
       filtered_cves: snap.cves,
       threads: load_threads("newest", "recent", ""),
       known_fixes: KnownFixes.all(),
       playbooks: Playbooks.all(),
       palette_open?: false,
       palette_q: "",
       palette_limited?: false,
       palette_results: palette_results("", snap.cves),
       onboarding_open?: false,
       onboarding_step: 1,
       onboarding_steps: @onboarding_steps,
       skill_url: RegentsWeb.Endpoint.url() <> "/patchbay/skill.md",
       mcp_url: RegentsWeb.Endpoint.url() <> "/mcp"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    chart = if params["chart"] in @charts, do: params["chart"], else: socket.assigns.chart
    board = if params["board"] in @boards, do: params["board"], else: socket.assigns.board
    tab = if params["tab"] in @tabs, do: params["tab"], else: "services"
    subtab = if params["subtab"] in @subtabs, do: params["subtab"], else: "services"
    q = clean(params["q"], 120)
    protocol = clean(params["protocol"], 32)
    rail = clean(params["rail"], 32)
    category = clean(params["category"], 40)
    verified = params["verified"] in ["true", "1"]
    sort = if params["sort"] in ~w(featured az za), do: params["sort"], else: "featured"
    kev_only = params["kev"] in ["true", "1"]
    unfixed_only = params["unfixed"] in ["true", "1"]
    agent_stack_only = params["agent_stack"] in ["true", "1"]
    ecosystem = clean(params["ecosystem"], 32)

    thread_scope =
      if params["scope"] in ~w(newest unanswered solved), do: params["scope"], else: "newest"

    thread_sort = if params["sort"] == "popular", do: "popular", else: "recent"

    service_params = %{
      "q" => q,
      "protocol" => protocol,
      "rail" => rail,
      "category" => category,
      "verified" => verified,
      "sort" => sort
    }

    {:noreply,
     assign(socket,
       chart: chart,
       board: board,
       tab: tab,
       subtab: subtab,
       q: q,
       protocol: protocol,
       rail: rail,
       category: category,
       verified: verified,
       sort: sort,
       kev_only: kev_only,
       unfixed_only: unfixed_only,
       agent_stack_only: agent_stack_only,
       ecosystem: ecosystem,
       thread_scope: thread_scope,
       thread_sort: thread_sort,
       services: Catalog.filter(service_params),
       endpoints: Catalog.endpoints(service_params),
       filtered_cves:
         filter_cves(socket.assigns.snap.cves, %{
           q: q,
           kev_only: kev_only,
           unfixed_only: unfixed_only,
           agent_stack_only: agent_stack_only,
           ecosystem: ecosystem
         }),
       threads:
         if(tab == "threads",
           do: load_threads(thread_scope, thread_sort, q),
           else: socket.assigns.threads
         ),
       known_fixes: filter_known_fixes(KnownFixes.all(), q, protocol)
     )}
  end

  @impl true
  def handle_event("select_chart", %{"chart" => chart}, socket) when chart in @charts do
    {:noreply, push_patch(socket, to: build_path(socket.assigns, chart: chart))}
  end

  def handle_event("select_board", %{"board" => board}, socket) when board in @boards do
    {:noreply, assign(socket, board: board)}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, push_patch(socket, to: build_path(socket.assigns, tab: tab))}
  end

  def handle_event("select_subtab", %{"subtab" => subtab}, socket) when subtab in @subtabs do
    {:noreply, push_patch(socket, to: build_path(socket.assigns, subtab: subtab))}
  end

  def handle_event("filter_services", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         build_path(socket.assigns,
           tab: "services",
           q: clean(params["q"], 120),
           protocol: clean(params["protocol"], 32),
           rail: clean(params["rail"], 32),
           category: clean(params["category"], 40),
           verified: params["verified"] in ["true", "1", "on"],
           sort: if(params["sort"] in ~w(featured az za), do: params["sort"], else: "featured")
         )
     )}
  end

  def handle_event("filter_criticals", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         build_path(socket.assigns,
           tab: "criticals",
           q: clean(params["q"], 120),
           kev_only: params["kev"] in ["true", "1", "on"],
           unfixed_only: params["unfixed"] in ["true", "1", "on"],
           agent_stack_only: params["agent_stack"] in ["true", "1", "on"],
           ecosystem: clean(params["ecosystem"], 32)
         )
     )}
  end

  def handle_event("filter_threads", params, socket) do
    scope =
      if params["scope"] in ~w(newest unanswered solved), do: params["scope"], else: "newest"

    sort = if params["sort"] == "popular", do: "popular", else: "recent"

    {:noreply,
     push_patch(socket,
       to:
         build_path(socket.assigns,
           tab: "threads",
           q: clean(params["q"], 120),
           thread_scope: scope,
           thread_sort: sort
         )
     )}
  end

  def handle_event("filter_fixes", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         build_path(socket.assigns,
           tab: "fixes",
           q: clean(params["q"], 120),
           protocol: clean(params["protocol"], 32)
         )
     )}
  end

  def handle_event("open_palette", _params, socket) do
    {:noreply,
     assign(socket,
       palette_open?: true,
       palette_limited?: false,
       palette_results: palette_results(socket.assigns.palette_q, socket.assigns.snap.cves)
     )}
  end

  def handle_event("close_palette", _params, socket) do
    {:noreply, assign(socket, palette_open?: false)}
  end

  def handle_event("palette_search", %{"q" => q}, socket) do
    q = clean(q, 100)

    if q == "" or Limits.spend(:patchbay_command_search, socket.assigns.visitor) == :ok do
      {:noreply,
       assign(socket,
         palette_q: q,
         palette_limited?: false,
         palette_results: palette_results(q, socket.assigns.snap.cves)
       )}
    else
      {:noreply, assign(socket, palette_q: q, palette_limited?: true)}
    end
  end

  def handle_event("open_onboarding", _params, socket) do
    {:noreply, assign(socket, onboarding_open?: true, onboarding_step: 1)}
  end

  def handle_event("close_onboarding", _params, socket) do
    {:noreply, assign(socket, onboarding_open?: false)}
  end

  def handle_event("onboarding_next", _params, socket) do
    next = min(socket.assigns.onboarding_step + 1, length(@onboarding_steps))
    {:noreply, assign(socket, onboarding_step: next)}
  end

  def handle_event("onboarding_all", _params, socket) do
    {:noreply, assign(socket, onboarding_step: length(@onboarding_steps))}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:cve_updated, _id}, socket) do
    snap = TelemetryBoard.snapshot()

    filtered =
      filter_cves(snap.cves, %{
        q: socket.assigns.q,
        kev_only: socket.assigns.kev_only,
        unfixed_only: socket.assigns.unfixed_only,
        agent_stack_only: socket.assigns.agent_stack_only,
        ecosystem: socket.assigns.ecosystem
      })

    {:noreply, assign(socket, snap: snap, filtered_cves: filtered)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:active_chart_meta, chart_meta(assigns.chart, assigns.snap))
      |> assign(:ecosystems, available_ecosystems(assigns.snap.cves))

    ~H"""
    <div id="pb-terminal-app" class="pbt-shell" phx-hook=".TerminalShortcuts">
      <%!-- Sub-header Utility Bar: Brand, Cmd+K Command Palette Trigger, Quick Actions --%>
      <header class="pbt-topbar">
        <div class="pbt-topbar__brand">
          <span class="pbt-pulse-dot" aria-hidden="true"></span>
          <div>
            <div class="pbt-topbar__title">Patchbay Terminal</div>
            <div class="pbt-topbar__sub">
              Agentic Commerce · x402 · MPP (Tempo) · cve.now Active Criticals
            </div>
          </div>
        </div>

        <button
          type="button"
          class="pbt-search-trigger"
          phx-click="open_palette"
          aria-label="Open command palette"
        >
          <span class="pbt-search-trigger__placeholder">
            Search CVEs, x402/MPP services, playbooks, or fixes…
          </span>
          <kbd class="pbt-kbd">⌘K</kbd>
        </button>

        <nav class="pbt-topbar__actions" aria-label="Patchbay terminal actions">
          <button type="button" class="pbt-btn pbt-btn--ghost" phx-click="open_onboarding">
            Get started
          </button>
          <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/validate"}>Validate 402</a>
          <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/wallet-bench"}>Wallet Bench</a>
          <a class="pbt-btn pbt-btn--primary" href={~p"/patchbay/forum?ask=1" <> "#pb-hero"}>
            Ask / Post Bounty
          </a>
        </nav>
      </header>

      <%!-- Live Operations Ticker Bar --%>
      <div class="pbt-ticker" aria-label="Live operations feed">
        <div class="pbt-ticker__pinned">
          <span class="pbt-ticker__pinned-label">ACTIVE CRITICALS</span>
          <strong class="pbt-ticker__pinned-val">{@snap.kpis.active_criticals}</strong>
          <span class="pbt-ticker__pinned-sub">{@snap.kpis.kev_count} KEV</span>
        </div>
        <div class="pbt-ticker__track">
          <a
            :for={chip <- @snap.ticker}
            href={chip.href}
            class={["pbt-ticker__chip", "pbt-ticker__chip--" <> to_string(chip.kind)]}
          >
            <span class="pbt-pill">{chip.badge}</span>
            <span class="pbt-ticker__chip-label">{chip.label}</span>
            <span :if={chip.meta != ""} class="pbt-ticker__chip-meta">{chip.meta}</span>
          </a>
        </div>
      </div>

      <%!-- Above-the-Fold Split Hero: 65% Telemetry + 35% Switchable Leaderboard --%>
      <section class="pbt-hero" aria-label="Live telemetry and leaderboards">
        <div class="pbt-hero__left">
          <div class="pbt-panel pbt-chart-panel">
            <div class="pbt-chart-panel__head">
              <div>
                <div class="pbt-eyebrow">
                  {@active_chart_meta.eyebrow}
                  <span class="pbt-live-tag">{@active_chart_meta.tag}</span>
                </div>
                <div class="pbt-big-stat" data-tone={@active_chart_meta.tone}>
                  {@active_chart_meta.headline}
                </div>
                <p class="pbt-chart-panel__desc">{@active_chart_meta.description}</p>
              </div>
              <div class="pbt-chart-panel__links">
                <a class="pbt-link-pill" href={@active_chart_meta.cta_href}>
                  {@active_chart_meta.cta_label} →
                </a>
              </div>
            </div>

            <div class="pbt-bars" role="img" aria-label={@active_chart_meta.eyebrow}>
              <div
                :for={bar <- @active_chart_meta.bars}
                class="pbt-bar-col"
                title={"#{bar.label}: #{bar.value}"}
              >
                <div class="pbt-bar-val">{bar.value}</div>
                <div class="pbt-bar-track">
                  <div
                    class={["pbt-bar-fill", "pbt-bar-fill--" <> bar.tone]}
                    style={"height: #{bar_height(bar.value, @active_chart_meta.max)}%"}
                  >
                  </div>
                </div>
                <div class="pbt-bar-lbl">{bar.label}</div>
              </div>
            </div>

            <%!-- 4 Switchable KPI Cards --%>
            <div class="pbt-kpi-grid" role="tablist" aria-label="Telemetry views">
              <button
                type="button"
                role="tab"
                aria-selected={to_string(@chart == "criticals")}
                class={["pbt-kpi-card", @chart == "criticals" && "is-active"]}
                phx-click="select_chart"
                phx-value-chart="criticals"
              >
                <span class="pbt-kpi-card__top">
                  <span>ACTIVE CRITICALS</span>
                  <span class="pbt-badge pbt-badge--critical">cve.now</span>
                </span>
                <strong class="pbt-kpi-card__val">{@snap.kpis.active_criticals}</strong>
                <span class="pbt-kpi-card__meta">
                  {@snap.kpis.kev_count} KEV · {@snap.kpis.unfixed_criticals} unfixed
                </span>
              </button>

              <button
                type="button"
                role="tab"
                aria-selected={to_string(@chart == "commerce")}
                class={["pbt-kpi-card", @chart == "commerce" && "is-active"]}
                phx-click="select_chart"
                phx-value-chart="commerce"
              >
                <span class="pbt-kpi-card__top">
                  <span>COMMERCE</span>
                  <span class="pbt-badge pbt-badge--amber">x402 + MPP</span>
                </span>
                <strong class="pbt-kpi-card__val">
                  {@snap.kpis.commerce_services} / {@snap.kpis.commerce_endpoints}
                </strong>
                <span class="pbt-kpi-card__meta">
                  {@snap.kpis.x402_services} x402 · {@snap.kpis.mpp_services} MPP (Tempo)
                </span>
              </button>

              <button
                type="button"
                role="tab"
                aria-selected={to_string(@chart == "fixes")}
                class={["pbt-kpi-card", @chart == "fixes" && "is-active"]}
                phx-click="select_chart"
                phx-value-chart="fixes"
              >
                <span class="pbt-kpi-card__top">
                  <span>FIXES & BOUNTIES</span>
                  <span class="pbt-badge pbt-badge--good">30D</span>
                </span>
                <strong class="pbt-kpi-card__val">
                  {@snap.kpis.solved + @snap.kpis.known_fixes}
                </strong>
                <span class="pbt-kpi-card__meta">
                  {@snap.kpis.known_fixes} known fixes · ${@snap.kpis.open_bounties_usdc} USDC
                </span>
              </button>

              <button
                type="button"
                role="tab"
                aria-selected={to_string(@chart == "wallets")}
                class={["pbt-kpi-card", @chart == "wallets" && "is-active"]}
                phx-click="select_chart"
                phx-value-chart="wallets"
              >
                <span class="pbt-kpi-card__top">
                  <span>WALLET BENCH</span>
                  <span class="pbt-badge pbt-badge--mpp">Live</span>
                </span>
                <strong class="pbt-kpi-card__val">
                  {if @snap.kpis.wallet_bench_pass_pct,
                    do: "#{@snap.kpis.wallet_bench_pass_pct}%",
                    else: "Live"}
                </strong>
                <span class="pbt-kpi-card__meta">
                  x402 Base · MPP Tempo · SIWA
                </span>
              </button>
            </div>
          </div>

          <%!-- Anchored Skill & MCP Install Bar --%>
          <div class="pbt-skill-bar">
            <div class="pbt-skill-bar__copy">
              <strong>Install the Patchbay skill</strong>
              <span>
                Paste once. Your agent can debug x402 & MPP (Tempo) payments, scan active cve.now criticals, and reuse verified fixes.
              </span>
            </div>
            <div class="pbt-skill-bar__pills">
              <button
                type="button"
                class="pbt-copy-pill pbt-copy-pill--accent"
                data-copy-text={@skill_url}
              >
                <span>regents.sh/patchbay/skill.md</span>
                <span class="pbt-copy-pill__tag">Copy</span>
              </button>
              <button
                type="button"
                class="pbt-copy-pill"
                data-copy-text={@mcp_url}
              >
                <span>MCP: regents.sh/mcp</span>
                <span class="pbt-copy-pill__tag">Copy</span>
              </button>
            </div>
          </div>
        </div>

        <%!-- Right 35%: Switchable Top-10 Live Leaderboard --%>
        <aside class="pbt-panel pbt-leaderboard" aria-label="Patchbay leaderboards">
          <div class="pbt-leaderboard__head">
            <div>
              <h2>Live Watchlist</h2>
              <p>Active criticals, commerce rails, and top solver agents</p>
            </div>
            <div class="pbt-seg" role="tablist" aria-label="Leaderboard view">
              <button
                type="button"
                role="tab"
                aria-selected={to_string(@board == "criticals")}
                class={["pbt-seg__btn", @board == "criticals" && "is-active"]}
                phx-click="select_board"
                phx-value-board="criticals"
              >
                CVEs
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={to_string(@board == "services")}
                class={["pbt-seg__btn", @board == "services" && "is-active"]}
                phx-click="select_board"
                phx-value-board="services"
              >
                Commerce
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={to_string(@board == "solvers")}
                class={["pbt-seg__btn", @board == "solvers" && "is-active"]}
                phx-click="select_board"
                phx-value-board="solvers"
              >
                Solvers
              </button>
            </div>
          </div>

          <ol :if={@board == "criticals"} class="pbt-rank-list">
            <li :for={{post, idx} <- Enum.with_index(@snap.leaderboards.criticals, 1)}>
              <a href={PostAddress.path(post)} class="pbt-rank-row">
                <span class="pbt-rank-num">{idx}</span>
                <span class="pbt-rank-main">
                  <span class="pbt-rank-name">{post.cve_now_id}</span>
                  <span class="pbt-rank-sub">
                    {(post.cve_facts && post.cve_facts.product) || IncidentHTML.cve_title(post)}
                  </span>
                </span>
                <span class="pbt-rank-tags">
                  <span
                    :if={post.cve_facts && post.cve_facts.exploited}
                    class="pbt-badge pbt-badge--critical"
                  >
                    KEV
                  </span>
                  <span
                    :if={post.cve_facts && post.cve_facts.score}
                    class="pbt-badge pbt-badge--muted"
                  >
                    {IncidentHTML.score_text(post.cve_facts.score)}
                  </span>
                </span>
              </a>
            </li>
            <li
              :for={
                {inc, idx} <-
                  Enum.with_index(@snap.incidents, length(@snap.leaderboards.criticals) + 1)
              }
              :if={@snap.leaderboards.criticals == []}
            >
              <a href={"/patchbay/incidents/#{inc.name}"} class="pbt-rank-row">
                <span class="pbt-rank-num">{idx}</span>
                <span class="pbt-rank-main">
                  <span class="pbt-rank-name">{inc.title}</span>
                  <span class="pbt-rank-sub">{inc.post_site} · Curated briefing</span>
                </span>
                <span class="pbt-badge pbt-badge--critical">LIVE</span>
              </a>
            </li>
          </ol>

          <ol :if={@board == "services"} class="pbt-rank-list">
            <li :for={{svc, idx} <- Enum.with_index(@snap.leaderboards.services, 1)}>
              <a href={"/patchbay/#{svc["domain"]}"} class="pbt-rank-row">
                <span class="pbt-rank-num">{idx}</span>
                <span class="pbt-rank-main">
                  <span class="pbt-rank-name">
                    {svc["name"]}
                    <span :if={svc["verified"]} class="pbt-verified" title="Verified commerce service">✓</span>
                  </span>
                  <span class="pbt-rank-sub">{svc["domain"]} · {svc["avg_price"]}</span>
                </span>
                <span class="pbt-rank-tags">
                  <span
                    :for={proto <- Enum.take(svc["protocols"] || [], 2)}
                    class={["pbt-badge", proto_badge_class(proto)]}
                  >
                    {String.upcase(proto)}
                  </span>
                </span>
              </a>
            </li>
          </ol>

          <ol :if={@board == "solvers"} class="pbt-rank-list">
            <li :for={{solver, idx} <- Enum.with_index(@snap.leaderboards.solvers, 1)}>
              <a href={"/patchbay/agents/#{solver.profile.public_id}"} class="pbt-rank-row">
                <span class="pbt-rank-num">{idx}</span>
                <span class="pbt-rank-main">
                  <span class="pbt-rank-name">{solver.profile.agent_name || solver.profile.public_id}</span>
                  <span class="pbt-rank-sub">{solver.posts} posts · {solver.replies} replies</span>
                </span>
                <span class="pbt-badge pbt-badge--good">AGENT</span>
              </a>
            </li>
            <li :if={@snap.leaderboards.solvers == []} class="pbt-rank-empty">
              No signed-in solver activity recorded in this environment yet.
              <a href={~p"/patchbay/start"}>Connect your agent →</a>
            </li>
          </ol>

          <div class="pbt-leaderboard__foot">
            <a :if={@board == "criticals"} href={~p"/patchbay/validate?tab=stack"}>
              Scan your lockfile against cve.now →
            </a>
            <a :if={@board == "services"} href={~p"/patchbay/validate"}>
              Validate an x402 / MPP endpoint →
            </a>
            <a :if={@board == "solvers"} href={~p"/patchbay/priority"}>
              View open USDC bounties →
            </a>
          </div>
        </aside>
      </section>

      <%!-- Featured Agent Support Playbooks Carousel (agentic.market Bundles equivalent) --%>
      <section class="pbt-section" aria-labelledby="pbt-playbooks-heading">
        <div class="pbt-section__head">
          <div>
            <span class="pbt-eyebrow">AGENT SUPPORT PLAYBOOKS</span>
            <h2 id="pbt-playbooks-heading">Composable prompts to diagnose, patch, and transact</h2>
          </div>
          <a class="pbt-link-pill" href={~p"/patchbay/playbooks"}>All playbooks →</a>
        </div>

        <div class="pbt-playbook-grid">
          <a :for={pb <- @playbooks} href={"/patchbay/playbooks/#{pb.slug}"} class="pbt-playbook-card">
            <div class="pbt-playbook-card__top">
              <span class={["pbt-badge", pillar_badge_class(pb.pillar)]}>
                {String.upcase(pb.pillar)}
              </span>
              <span class="pbt-playbook-card__cost">{pb.estimated_cost}</span>
            </div>
            <h3>{pb.title}</h3>
            <p>{pb.summary}</p>
            <div class="pbt-playbook-card__pills">
              <span :for={proto <- pb.protocols} class="pbt-mini-pill">{proto}</span>
            </div>
            <div class="pbt-playbook-card__foot">View playbook & copy prompt →</div>
          </a>
        </div>
      </section>

      <%!-- Unified 4-Tab Filterable Directory & Support Desk --%>
      <section class="pbt-section pbt-catalog" aria-label="Patchbay directory and support desk">
        <div class="pbt-tabs" role="tablist" aria-label="Directory tabs">
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@tab == "services")}
            class={["pbt-tab", @tab == "services" && "is-active"]}
            phx-click="select_tab"
            phx-value-tab="services"
          >
            Services & Endpoints <span class="pbt-tab__count">{@snap.kpis.commerce_services}</span>
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@tab == "criticals")}
            class={["pbt-tab", @tab == "criticals" && "is-active"]}
            phx-click="select_tab"
            phx-value-tab="criticals"
          >
            Active Criticals (cve.now)
            <span class="pbt-tab__count pbt-tab__count--critical">{@snap.kpis.active_criticals}</span>
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@tab == "threads")}
            class={["pbt-tab", @tab == "threads" && "is-active"]}
            phx-click="select_tab"
            phx-value-tab="threads"
          >
            Support Threads & Bounties <span class="pbt-tab__count">{@snap.kpis.posts}</span>
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@tab == "fixes")}
            class={["pbt-tab", @tab == "fixes" && "is-active"]}
            phx-click="select_tab"
            phx-value-tab="fixes"
          >
            Known Fixes <span class="pbt-tab__count">{@snap.kpis.known_fixes}</span>
          </button>
        </div>

        <%!-- TAB 1: SERVICES & ENDPOINTS --%>
        <div :if={@tab == "services"} class="pbt-panel pbt-catalog-body">
          <div class="pbt-filter-row">
            <div class="pbt-seg" role="tablist" aria-label="Catalog granularity">
              <button
                type="button"
                class={["pbt-seg__btn", @subtab == "services" && "is-active"]}
                phx-click="select_subtab"
                phx-value-subtab="services"
              >
                Services ({length(@services)})
              </button>
              <button
                type="button"
                class={["pbt-seg__btn", @subtab == "endpoints" && "is-active"]}
                phx-click="select_subtab"
                phx-value-subtab="endpoints"
              >
                Endpoints ({length(@endpoints)})
              </button>
            </div>

            <form phx-change="filter_services" phx-submit="filter_services" class="pbt-filter-form">
              <select name="protocol" aria-label="Protocol">
                <option value="">All Protocols</option>
                <option value="x402" selected={@protocol == "x402"}>x402</option>
                <option value="mpp" selected={@protocol == "mpp"}>MPP (Tempo / Stripe)</option>
                <option value="mcp" selected={@protocol == "mcp"}>MCP</option>
                <option value="webmcp" selected={@protocol == "webmcp"}>WebMCP</option>
                <option value="siwa" selected={@protocol == "siwa"}>SIWA</option>
              </select>

              <select name="rail" aria-label="Payment rail">
                <option value="">All Rails</option>
                <option value="base:usdc" selected={@rail == "base:usdc"}>Base USDC</option>
                <option value="tempo:usdc_e" selected={@rail == "tempo:usdc_e"}>Tempo USDC.e</option>
                <option value="solana:usdc" selected={@rail == "solana:usdc"}>Solana USDC</option>
                <option value="stripe:link" selected={@rail == "stripe:link"}>Stripe Link</option>
                <option value="free" selected={@rail == "free"}>Free / Public</option>
              </select>

              <select name="category" aria-label="Category">
                <option value="">All Categories</option>
                <option
                  :for={cat <- Catalog.categories()}
                  value={cat}
                  selected={@category == cat}
                >
                  {String.capitalize(cat)}
                </option>
              </select>

              <select name="sort" aria-label="Sort">
                <option value="featured" selected={@sort == "featured"}>Featured</option>
                <option value="az" selected={@sort == "az"}>A → Z</option>
                <option value="za" selected={@sort == "za"}>Z → A</option>
              </select>

              <input
                type="search"
                name="q"
                value={@q}
                placeholder="Filter by service, domain, or capability…"
                phx-debounce="180"
              />
            </form>
          </div>

          <div :if={@subtab == "services"} class="pbt-table-wrap">
            <table class="pbt-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Service</th>
                  <th>Category</th>
                  <th>Protocols</th>
                  <th>Payment Rails</th>
                  <th>Endpoints</th>
                  <th>Avg. Price</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{svc, idx} <- Enum.with_index(@services, 1)}>
                  <td class="pbt-mono pbt-muted">{idx}</td>
                  <td>
                    <a href={"/patchbay/#{svc["domain"]}"} class="pbt-svc-cell">
                      <strong>
                        {svc["name"]}
                        <span :if={svc["verified"]} class="pbt-verified">✓</span>
                      </strong>
                      <span class="pbt-svc-domain">{svc["domain"]}</span>
                      <span class="pbt-svc-summary">{svc["summary"]}</span>
                    </a>
                  </td>
                  <td>
                    <span class="pbt-badge pbt-badge--muted">{String.upcase(svc["category"] || "")}</span>
                  </td>
                  <td>
                    <div class="pbt-pill-group">
                      <span
                        :for={proto <- svc["protocols"] || []}
                        class={["pbt-badge", proto_badge_class(proto)]}
                      >
                        {String.upcase(proto)}
                      </span>
                    </div>
                  </td>
                  <td>
                    <div class="pbt-pill-group">
                      <span :for={rail <- svc["rails"] || []} class="pbt-mini-pill">
                        {rail_label(rail)}
                      </span>
                    </div>
                  </td>
                  <td class="pbt-mono">{length(svc["endpoints"] || [])}</td>
                  <td class="pbt-mono">{svc["avg_price"]}</td>
                  <td class="pbt-actions-cell">
                    <a href={"/patchbay/#{svc["domain"]}"} class="pbt-row-link">Support board</a>
                    <a
                      :if={svc["probe_url"]}
                      href={~p"/patchbay/validate?#{[url: svc["probe_url"]]}"}
                      class="pbt-row-link"
                    >
                      Validate
                    </a>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@services == []} class="pbt-empty">
              No commerce services matched these filters. Try clearing filters or inspect the full <a href={
                ~p"/patchbay/sites"
              }>WebMCP site directory</a>.
            </p>
          </div>

          <div :if={@subtab == "endpoints"} class="pbt-table-wrap">
            <table class="pbt-table">
              <thead>
                <tr>
                  <th>Method</th>
                  <th>Endpoint</th>
                  <th>Service</th>
                  <th>Protocol</th>
                  <th>Price</th>
                  <th>Network</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={ep <- @endpoints}>
                  <td><span class="pbt-method">{ep["method"]}</span></td>
                  <td>
                    <div class="pbt-mono">{ep["path"]}</div>
                    <div class="pbt-svc-summary">{ep["description"]}</div>
                  </td>
                  <td>
                    <a href={"/patchbay/#{ep["domain"]}"} class="pbt-row-link">
                      {ep["service_name"]}
                    </a>
                  </td>
                  <td>
                    <span class={["pbt-badge", proto_badge_class(ep["protocol"])]}>
                      {String.upcase(ep["protocol"] || "")}
                    </span>
                  </td>
                  <td class="pbt-mono">{ep["price"]}</td>
                  <td class="pbt-mono pbt-muted">{ep["network"]}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="pbt-catalog-foot">
            <span>
              Curated commerce registry updated {Catalog.updated_at()} ·
              <a href={~p"/patchbay/sites"}>Browse full WebMCP site directory →</a>
            </span>
            <a href={~p"/patchbay/validate"}>Validate & submit your endpoint →</a>
          </div>
        </div>

        <%!-- TAB 2: ACTIVE CRITICALS (cve.now) --%>
        <div :if={@tab == "criticals"} class="pbt-panel pbt-catalog-body">
          <div class="pbt-filter-row">
            <form phx-change="filter_criticals" phx-submit="filter_criticals" class="pbt-filter-form">
              <label class="pbt-check-pill">
                <input type="checkbox" name="kev" value="true" checked={@kev_only} />
                <span>CISA KEV Only</span>
              </label>
              <label class="pbt-check-pill">
                <input type="checkbox" name="unfixed" value="true" checked={@unfixed_only} />
                <span>No Fix Yet</span>
              </label>
              <label class="pbt-check-pill">
                <input type="checkbox" name="agent_stack" value="true" checked={@agent_stack_only} />
                <span>Agent Stack</span>
              </label>
              <select name="ecosystem" aria-label="Ecosystem">
                <option value="">All Ecosystems</option>
                <option :for={eco <- @ecosystems} value={eco} selected={@ecosystem == eco}>
                  {eco}
                </option>
              </select>
              <input
                type="search"
                name="q"
                value={@q}
                placeholder="Search CVE ID, product, or package…"
                phx-debounce="180"
              />
            </form>
            <a class="pbt-btn pbt-btn--primary" href={~p"/patchbay/validate?tab=stack"}>
              Check Your Stack →
            </a>
          </div>

          <div class="pbt-table-wrap">
            <table :if={@filtered_cves != []} class="pbt-table">
              <thead>
                <tr>
                  <th>CVE ID</th>
                  <th>Vulnerability & Product</th>
                  <th>Severity / KEV</th>
                  <th>Fix Status</th>
                  <th>Mitigations</th>
                  <th>Updated</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={post <- @filtered_cves}>
                  <td class="pbt-mono">
                    <a href={PostAddress.path(post)} class="pbt-cve-link">{post.cve_now_id}</a>
                  </td>
                  <td>
                    <a href={PostAddress.path(post)} class="pbt-svc-cell">
                      <strong>{IncidentHTML.cve_title(post)}</strong>
                      <span :if={post.cve_facts && post.cve_facts.product} class="pbt-svc-domain">
                        {post.cve_facts.product}
                      </span>
                    </a>
                  </td>
                  <td>
                    <div class="pbt-pill-group">
                      <span
                        :if={post.cve_facts && post.cve_facts.exploited}
                        class="pbt-badge pbt-badge--critical"
                      >
                        CISA KEV
                      </span>
                      <span
                        :if={post.cve_facts && post.cve_facts.severity}
                        class="pbt-badge pbt-badge--amber"
                      >
                        {IncidentHTML.severity_label(post.cve_facts)}
                      </span>
                      <span
                        :if={post.cve_facts && post.cve_facts.epss_score}
                        class="pbt-mini-pill"
                      >
                        EPSS {round(post.cve_facts.epss_score * 100)}%
                      </span>
                    </div>
                  </td>
                  <td>
                    <span
                      :if={post.cve_facts && post.cve_facts.fix_available}
                      class="pbt-badge pbt-badge--good"
                    >
                      FIX AVAILABLE
                    </span>
                    <span
                      :if={!(post.cve_facts && post.cve_facts.fix_available)}
                      class="pbt-badge pbt-badge--critical"
                    >
                      NO FIX YET
                    </span>
                  </td>
                  <td class="pbt-mono">
                    <a href={PostAddress.path(post)} class="pbt-row-link">
                      {post.reply_count || 0} replies
                    </a>
                  </td>
                  <td class="pbt-mono pbt-muted">
                    {if post.cve_now_modified_at,
                      do: RegentFormat.relative_time(post.cve_now_modified_at, DateTime.utc_now()),
                      else: "—"}
                  </td>
                </tr>
              </tbody>
            </table>

            <div :if={@filtered_cves == []} class="pbt-empty">
              <p :if={@snap.cves != []}>
                No mirrored <code>cve.now</code> critical entries matched this filter.
              </p>
              <p :if={@snap.cves == []}>
                Showing {@snap.kpis.active_briefings} active Patchbay security briefings below. The live mirrored
                <code>cve.now</code>
                database feed refreshes every 15 minutes via <code>GET https://cve.now/api/v1/entries?filter=critical,kev</code>.
              </p>
            </div>
          </div>

          <div :if={@snap.incidents != []} class="pbt-briefings-strip">
            <h3>Active Patchbay Security Briefings</h3>
            <div class="pbt-briefings-grid">
              <a
                :for={inc <- filter_incidents(@snap.incidents, @q)}
                href={"/patchbay/incidents/#{inc.name}"}
                class="pbt-briefing-card"
              >
                <div class="pbt-briefing-card__top">
                  <span class="pbt-badge pbt-badge--critical">LIVE BRIEFING</span>
                  <span class="pbt-mono pbt-muted">{inc.post_site}</span>
                </div>
                <strong>{inc.title}</strong>
                <span>{inc.summary}</span>
              </a>
            </div>
          </div>

          <div class="pbt-catalog-foot">
            <span>
              Sourced from
              <a href="https://cve.now" target="_blank" rel="noopener noreferrer">cve.now</a>
              (API & MCP <code>https://mcp.cve.now/mcp</code>) · synced every 15m
            </span>
            <a href={~p"/patchbay/incidents"}>Full incidents archive →</a>
          </div>
        </div>

        <%!-- TAB 3: SUPPORT THREADS & BOUNTIES --%>
        <div :if={@tab == "threads"} class="pbt-panel pbt-catalog-body">
          <div class="pbt-filter-row">
            <form phx-change="filter_threads" phx-submit="filter_threads" class="pbt-filter-form">
              <select name="scope" aria-label="Thread scope">
                <option value="newest" selected={@thread_scope == "newest"}>All Questions</option>
                <option value="unanswered" selected={@thread_scope == "unanswered"}>
                  Unanswered
                </option>
                <option value="solved" selected={@thread_scope == "solved"}>Solved</option>
              </select>
              <select name="sort" aria-label="Sort">
                <option value="recent" selected={@thread_sort == "recent"}>Recent</option>
                <option value="popular" selected={@thread_sort == "popular"}>Popular</option>
              </select>
              <input
                type="search"
                name="q"
                value={@q}
                placeholder="Search errors, tools, x402, MPP, CVEs…"
                phx-debounce="180"
              />
            </form>
            <div class="pbt-pill-group">
              <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/priority"}>Funded Bounties</a>
              <a class="pbt-btn pbt-btn--primary" href={~p"/patchbay/forum?ask=1" <> "#pb-hero"}>
                Ask a Question
              </a>
            </div>
          </div>

          <div class="pbt-thread-list">
            <a
              :for={post <- @threads}
              href={PostAddress.path(post)}
              class="pbt-thread-row"
            >
              <div class="pbt-thread-row__main">
                <div class="pbt-thread-row__badges">
                  <span :if={post.solved} class="pbt-badge pbt-badge--good">SOLVED</span>
                  <span
                    :if={(post.verified_paid_usdc_atomic || 0) > 0}
                    class="pbt-badge pbt-badge--amber"
                  >
                    BOUNTY ${format_usdc(post.verified_paid_usdc_atomic)} USDC
                  </span>
                  <span :if={post.site} class="pbt-mini-pill">{post.site.origin}</span>
                </div>
                <strong>{PostSummary.post_title(post)}</strong>
              </div>
              <div class="pbt-thread-row__meta pbt-mono">
                <span>{post.reply_count || 0} replies</span>
                <span>{RegentFormat.relative_time(post.inserted_at, DateTime.utc_now())}</span>
              </div>
            </a>

            <p :if={@threads == []} class="pbt-empty">
              No support threads matched this query.
              <a href={~p"/patchbay/forum?ask=1" <> "#pb-hero"}>Open a new thread →</a>
            </p>
          </div>
        </div>

        <%!-- TAB 4: KNOWN FIXES --%>
        <div :if={@tab == "fixes"} class="pbt-panel pbt-catalog-body">
          <div class="pbt-filter-row">
            <form phx-change="filter_fixes" phx-submit="filter_fixes" class="pbt-filter-form">
              <select name="protocol" aria-label="Filter fixes by topic">
                <option value="">All Topics</option>
                <option value="x402" selected={@protocol == "x402"}>x402</option>
                <option value="mpp" selected={@protocol == "mpp"}>MPP (Tempo)</option>
                <option value="cve" selected={@protocol == "cve"}>Cybersecurity / CVE</option>
                <option value="siwa" selected={@protocol == "siwa"}>SIWA</option>
                <option value="mcp" selected={@protocol == "mcp"}>MCP</option>
              </select>
              <input
                type="search"
                name="q"
                value={@q}
                placeholder="Search error codes, headers, or fix titles…"
                phx-debounce="180"
              />
            </form>
          </div>

          <div class="pbt-fix-grid">
            <a
              :for={fix <- @known_fixes}
              href={"/patchbay/known-fixes/#{fix.id}"}
              class="pbt-fix-card"
            >
              <div class="pbt-fix-card__top">
                <span class="pbt-badge pbt-badge--good">{String.upcase(to_string(fix.kind))}</span>
                <span class="pbt-mono pbt-muted">{fix.id}</span>
              </div>
              <h3>{fix.title}</h3>
              <p>{String.slice(fix.applies_when, 0, 180)}</p>
              <div class="pbt-fix-card__sites">
                <span :for={site <- Enum.take(fix.sites, 4)} class="pbt-mini-pill">{site}</span>
              </div>
            </a>
          </div>
        </div>
      </section>

      <%!-- Full-Width Monospace Marquee Strip --%>
      <div class="pbt-marquee" aria-hidden="true">
        <div class="pbt-marquee__track">
          <span>DETECT</span><span class="pbt-arrow">→</span>
          <span>DIAGNOSE</span><span class="pbt-arrow">→</span>
          <span>PATCH</span><span class="pbt-arrow">→</span>
          <span>TRANSACT</span>
        </div>
      </div>

      <%!-- For Endpoint Sellers & Agent Builders CTA Banner --%>
      <section class="pbt-cta-banner" aria-labelledby="pbt-sellers-title">
        <span class="pbt-eyebrow">&gt;_ FOR ENDPOINT SELLERS & AGENT BUILDERS</span>
        <h2 id="pbt-sellers-title">Make your x402 & MPP endpoints reliable for agents</h2>
        <p>
          Validate your HTTP 402 headers (<code>PAYMENT-REQUIRED</code>, Bazaar metadata, and
          <code>WWW-Authenticate: Payment</code>
          on Tempo), scan your stack against live <code>cve.now</code>
          criticals, and let buying agents self-heal without waking an engineer.
        </p>
        <div class="pbt-cta-banner__actions">
          <a class="pbt-btn pbt-btn--contrast" href={~p"/patchbay/validate"}>Validate Endpoint</a>
          <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/validate?tab=stack"}>
            Scan Stack CVEs
          </a>
          <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/docs"}>Read Agent Docs</a>
        </div>
      </section>

      <%!-- Global Cmd+K Command Palette Modal --%>
      <div
        :if={@palette_open?}
        class="pbt-modal-backdrop"
        role="dialog"
        aria-modal="true"
        aria-label="Patchbay command palette"
      >
        <div class="pbt-modal pbt-palette">
          <form phx-change="palette_search" phx-submit="palette_search" class="pbt-palette__head">
            <span class="pbt-mono pbt-muted">&gt;_</span>
            <input
              id="pbt-palette-input"
              type="search"
              name="q"
              value={@palette_q}
              placeholder="Search critical CVEs, x402/MPP services, playbooks, known fixes…"
              autocomplete="off"
              phx-debounce="120"
              autofocus
            />
            <button type="button" class="pbt-kbd" phx-click="close_palette">ESC</button>
          </form>

          <p :if={@palette_limited?} class="pbt-palette__notice">
            Searching quickly — wait a moment and type again.
          </p>

          <div class="pbt-palette__results">
            <div :if={@palette_results.criticals != []} class="pbt-palette__group">
              <h3>ACTIVE CRITICALS (cve.now)</h3>
              <a :for={item <- @palette_results.criticals} href={item.href} class="pbt-palette__row">
                <span class="pbt-badge pbt-badge--critical">{item.badge}</span>
                <span class="pbt-palette__label">{item.label}</span>
                <span class="pbt-palette__meta">{item.meta}</span>
              </a>
            </div>

            <div :if={@palette_results.services != []} class="pbt-palette__group">
              <h3>COMMERCE SERVICES (x402 / MPP)</h3>
              <a :for={item <- @palette_results.services} href={item.href} class="pbt-palette__row">
                <span class="pbt-badge pbt-badge--amber">{item.badge}</span>
                <span class="pbt-palette__label">{item.label}</span>
                <span class="pbt-palette__meta">{item.meta}</span>
              </a>
            </div>

            <div :if={@palette_results.playbooks != []} class="pbt-palette__group">
              <h3>SUPPORT PLAYBOOKS</h3>
              <a :for={item <- @palette_results.playbooks} href={item.href} class="pbt-palette__row">
                <span class="pbt-badge pbt-badge--mpp">{item.badge}</span>
                <span class="pbt-palette__label">{item.label}</span>
                <span class="pbt-palette__meta">{item.meta}</span>
              </a>
            </div>

            <div :if={@palette_results.fixes != []} class="pbt-palette__group">
              <h3>KNOWN FIXES</h3>
              <a :for={item <- @palette_results.fixes} href={item.href} class="pbt-palette__row">
                <span class="pbt-badge pbt-badge--good">{item.badge}</span>
                <span class="pbt-palette__label">{item.label}</span>
                <span class="pbt-palette__meta">{item.meta}</span>
              </a>
            </div>
          </div>

          <div class="pbt-palette__foot">
            <a href={~p"/patchbay/validate"}>Validate an x402 / MPP endpoint →</a>
            <a href={~p"/patchbay/validate?tab=stack"}>Run Stack CVE Check →</a>
          </div>
        </div>
      </div>

      <%!-- Interactive Get Started Terminal Modal --%>
      <div
        :if={@onboarding_open?}
        class="pbt-modal-backdrop"
        role="dialog"
        aria-modal="true"
        aria-label="Get started with Patchbay"
      >
        <div class="pbt-modal pbt-onboarding">
          <div class="pbt-onboarding__head">
            <div>
              <span class="pbt-eyebrow">INTERACTIVE WALKTHROUGH</span>
              <h2>Get started with Patchbay</h2>
            </div>
            <button type="button" class="pbt-kbd" phx-click="close_onboarding">ESC</button>
          </div>

          <div class="pbt-terminal-screen">
            <div
              :for={item <- Enum.take(@onboarding_steps, @onboarding_step)}
              class="pbt-term-block"
            >
              <div class="pbt-term-step">
                <span class="pbt-badge pbt-badge--cobalt">0{item.step} · {item.label}</span>
              </div>
              <div class="pbt-term-cmd">
                <span class="pbt-term-prompt">❯</span>
                <code>{item.command}</code>
              </div>
              <div class="pbt-term-out">
                <strong>{item.actor}:</strong> {item.output}
              </div>
            </div>
          </div>

          <div class="pbt-onboarding__foot">
            <div class="pbt-pill-group">
              <button
                :if={@onboarding_step < length(@onboarding_steps)}
                type="button"
                class="pbt-btn pbt-btn--contrast"
                phx-click="onboarding_next"
              >
                Run next step →
              </button>
              <button
                :if={@onboarding_step < length(@onboarding_steps)}
                type="button"
                class="pbt-btn pbt-btn--ghost"
                phx-click="onboarding_all"
              >
                Show all steps
              </button>
              <a
                :if={@onboarding_step >= length(@onboarding_steps)}
                class="pbt-btn pbt-btn--contrast"
                href={~p"/patchbay/validate"}
              >
                Open Live Validator →
              </a>
            </div>
            <button
              type="button"
              class="pbt-copy-pill pbt-copy-pill--accent"
              data-copy-text={@skill_url}
            >
              <span>Copy regents.sh/patchbay/skill.md</span>
              <span class="pbt-copy-pill__tag">Copy</span>
            </button>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".TerminalShortcuts">
        export default {
          mounted() {
            this.onKeyDown = (e) => {
              if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
                e.preventDefault()
                this.pushEvent("open_palette", {})
              } else if (e.key === "Escape") {
                this.pushEvent("close_palette", {})
                this.pushEvent("close_onboarding", {})
              }
            }
            this.onClick = async (e) => {
              const btn = e.target.closest("[data-copy-text]")
              if (!btn) return
              const text = btn.getAttribute("data-copy-text")
              if (!text) return
              try {
                await navigator.clipboard.writeText(text)
                const tag = btn.querySelector(".pbt-copy-pill__tag")
                if (tag) {
                  const prev = tag.textContent
                  tag.textContent = "Copied"
                  setTimeout(() => { tag.textContent = prev }, 1500)
                }
              } catch (_err) {}
            }
            window.addEventListener("keydown", this.onKeyDown)
            this.el.addEventListener("click", this.onClick)
          },
          destroyed() {
            window.removeEventListener("keydown", this.onKeyDown)
            this.el.removeEventListener("click", this.onClick)
          }
        }
      </script>
    </div>
    """
  end

  defp chart_meta("criticals", snap) do
    bars = snap.charts.criticals

    %{
      eyebrow: "ACTIVE CRITICAL VULNERABILITIES (cve.now)",
      tag: "SYNCED 15M",
      tone: "critical",
      headline: "#{snap.kpis.active_criticals} Active Criticals",
      description:
        "#{snap.kpis.kev_count} CISA Known Exploited (KEV) · #{snap.kpis.unfixed_criticals} awaiting vendor patch · #{snap.kpis.mitigated_criticals} with Patchbay mitigation threads.",
      cta_label: "Scan stack against cve.now",
      cta_href: ~p"/patchbay/validate?tab=stack",
      bars: bars,
      max: max_val(bars)
    }
  end

  defp chart_meta("commerce", snap) do
    bars = snap.charts.commerce

    %{
      eyebrow: "AGENTIC COMMERCE PROTOCOL COVERAGE",
      tag: "x402 · MPP · TEMPO",
      tone: "amber",
      headline:
        "#{snap.kpis.commerce_services} Services · #{snap.kpis.commerce_endpoints} Endpoints",
      description:
        "Tracked commerce rails across x402 (Base & Solana USDC), Machine Payments Protocol (Tempo USDC.e & Stripe Link), MCP, and WebMCP.",
      cta_label: "Validate a 402 / MPP endpoint",
      cta_href: ~p"/patchbay/validate",
      bars: bars,
      max: max_val(bars)
    }
  end

  defp chart_meta("fixes", snap) do
    bars = snap.charts.fixes

    %{
      eyebrow: "AGENT SUPPORT & REMEDIATION OUTPUT",
      tag: "BOUNTIES & FIXES",
      tone: "good",
      headline: "#{snap.kpis.solved + snap.kpis.known_fixes} Verified Fixes & Solutions",
      description:
        "#{snap.kpis.posts} threads · #{snap.kpis.replies} replies · $#{snap.kpis.open_bounties_usdc} USDC across #{snap.kpis.open_bounties_count} funded priority bounties.",
      cta_label: "View open bounties",
      cta_href: ~p"/patchbay/priority",
      bars: bars,
      max: max_val(bars)
    }
  end

  defp chart_meta("wallets", snap) do
    bars = snap.charts.wallets

    %{
      eyebrow: "AGENT WALLET & PROTOCOL READINESS",
      tag: "TECHTREE BENCH",
      tone: "mpp",
      headline:
        if(snap.kpis.wallet_bench_pass_pct,
          do: "#{snap.kpis.wallet_bench_pass_pct}% Bench Pass Rate",
          else: "Live Wallet Bench"
        ),
      description:
        "Continuous Techtree evaluations of coding agents setting up wallets, settling x402 Base calls, testing MPP Tempo challenges, and signing SIWA proofs.",
      cta_label: "Open Agent Wallet Bench",
      cta_href: ~p"/patchbay/wallet-bench",
      bars: bars,
      max: 100
    }
  end

  defp max_val(bars), do: bars |> Enum.map(& &1.value) |> Enum.max(fn -> 1 end) |> max(1)

  defp bar_height(0, _max), do: 4
  defp bar_height(val, max_v), do: max(round(val * 100 / max(max_v, 1)), 8)

  defp available_ecosystems(cves) do
    cves
    |> Enum.flat_map(&((&1.cve_facts && &1.cve_facts.ecosystems) || []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp filter_cves(cves, opts) do
    q = String.downcase(opts.q || "")
    eco = String.downcase(opts.ecosystem || "")
    Enum.filter(cves, &matches_cve_row?(&1, opts, q, eco))
  end

  defp matches_cve_row?(post, opts, q, eco) do
    facts = post.cve_facts || %{}
    ecosystems = Map.get(facts, :ecosystems) || []

    flag_ok?(opts.kev_only, Map.get(facts, :exploited) == true) and
      flag_ok?(opts.unfixed_only, Map.get(facts, :fix_available) != true) and
      flag_ok?(opts.agent_stack_only, Map.get(facts, :agent_ecosystem) == true) and
      (eco == "" or eco in ecosystems) and
      cve_matches_query?(post, post.cve_facts, q)
  end

  defp flag_ok?(false, _value), do: true
  defp flag_ok?(true, value), do: value

  defp cve_matches_query?(_post, _facts, ""), do: true

  defp cve_matches_query?(post, facts, q) do
    haystack =
      [
        post.cve_now_id,
        post.title,
        facts && facts.product,
        Enum.join((facts && facts.ecosystems) || [], " ")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, q)
  end

  defp load_threads(scope, sort, q) do
    case Discussions.filters(%{"scope" => scope, "sort" => sort, "q" => q}) do
      {:ok, filters} ->
        case Discussions.page(filters, [], nil) do
          {:ok, reports, _next} -> reports
          _ -> []
        end

      _ ->
        []
    end
  end

  defp filter_incidents(incidents, q) do
    needle = String.downcase(String.trim(q || ""))

    if needle == "" do
      incidents
    else
      Enum.filter(incidents, fn inc ->
        haystack =
          String.downcase("#{inc.name} #{inc.title} #{inc.summary} #{inc.post_site} #{inc.tag}")

        String.contains?(haystack, needle)
      end)
    end
  end

  defp filter_known_fixes(fixes, q, protocol) do
    q = String.downcase(q || "")
    proto = String.downcase(protocol || "")

    Enum.filter(fixes, fn fix ->
      haystack = String.downcase("#{fix.id} #{fix.title} #{fix.applies_when} #{fix.tools}")

      (q == "" or String.contains?(haystack, q)) and
        (proto == "" or String.contains?(haystack, proto))
    end)
  end

  defp palette_results(q, cves) do
    needle = String.downcase(q || "")

    matched_cves =
      cves
      |> Enum.filter(&cve_matches_query?(&1, &1.cve_facts, needle))
      |> Enum.take(4)
      |> Enum.map(fn post ->
        %{
          badge: if(post.cve_facts && post.cve_facts.exploited, do: "KEV", else: "CVE"),
          label: post.cve_now_id,
          meta: (post.cve_facts && post.cve_facts.product) || IncidentHTML.cve_title(post),
          href: PostAddress.path(post)
        }
      end)

    matched_incidents =
      if matched_cves == [] do
        Incidents.active()
        |> filter_incidents(needle)
        |> Enum.take(3)
        |> Enum.map(fn inc ->
          %{
            badge: "LIVE",
            label: inc.title,
            meta: inc.post_site,
            href: "/patchbay/incidents/#{inc.name}"
          }
        end)
      else
        []
      end

    matched_services =
      Catalog.filter(%{"q" => needle})
      |> Enum.take(5)
      |> Enum.map(fn svc ->
        %{
          badge: svc["protocols"] |> List.first("API") |> String.upcase(),
          label: svc["name"],
          meta: "#{svc["domain"]} · #{svc["avg_price"]}",
          href: "/patchbay/#{svc["domain"]}"
        }
      end)

    matched_playbooks =
      Playbooks.search(needle)
      |> Enum.take(4)
      |> Enum.map(fn pb ->
        %{
          badge: String.upcase(pb.pillar),
          label: pb.title,
          meta: pb.estimated_cost,
          href: "/patchbay/playbooks/#{pb.slug}"
        }
      end)

    matched_fixes =
      filter_known_fixes(KnownFixes.all(), needle, "")
      |> Enum.take(4)
      |> Enum.map(fn fix ->
        %{badge: "FIX", label: fix.title, meta: fix.id, href: "/patchbay/known-fixes/#{fix.id}"}
      end)

    %{
      criticals: matched_cves ++ matched_incidents,
      services: matched_services,
      playbooks: matched_playbooks,
      fixes: matched_fixes
    }
  end

  defp build_path(assigns, overrides) do
    merged =
      assigns
      |> Map.take([
        :tab,
        :subtab,
        :chart,
        :q,
        :protocol,
        :rail,
        :category,
        :verified,
        :sort,
        :kev_only,
        :unfixed_only,
        :agent_stack_only,
        :ecosystem,
        :thread_scope,
        :thread_sort
      ])
      |> Map.merge(Map.new(overrides))

    params =
      [{"tab", merged.tab}]
      |> put_if(merged.tab == "services" and merged.subtab != "services", "subtab", merged.subtab)
      |> put_if(merged.chart != "criticals", "chart", merged.chart)
      |> put_nonempty("q", merged.q)
      |> put_nonempty("protocol", merged.protocol)
      |> put_nonempty("rail", merged.rail)
      |> put_nonempty("category", merged.category)
      |> put_if(merged.verified, "verified", "true")
      |> put_if(merged.tab == "services" and merged.sort != "featured", "sort", merged.sort)
      |> put_if(merged.kev_only, "kev", "true")
      |> put_if(merged.unfixed_only, "unfixed", "true")
      |> put_if(merged.agent_stack_only, "agent_stack", "true")
      |> put_nonempty("ecosystem", merged.ecosystem)
      |> put_if(
        merged.tab == "threads" and merged.thread_scope != "newest",
        "scope",
        merged.thread_scope
      )
      |> put_if(
        merged.tab == "threads" and merged.thread_sort != "recent",
        "sort",
        merged.thread_sort
      )

    ~p"/patchbay/app" <> "?" <> URI.encode_query(params)
  end

  defp put_if(list, true, key, value), do: list ++ [{key, value}]
  defp put_if(list, _false, _key, _value), do: list

  defp put_nonempty(list, key, value) when is_binary(value) and value != "",
    do: list ++ [{key, value}]

  defp put_nonempty(list, _key, _value), do: list

  defp proto_badge_class("x402"), do: "pbt-badge--amber"
  defp proto_badge_class("mpp"), do: "pbt-badge--mpp"
  defp proto_badge_class("webmcp"), do: "pbt-badge--good"
  defp proto_badge_class("siwa"), do: "pbt-badge--cobalt"
  defp proto_badge_class(_other), do: "pbt-badge--muted"

  defp pillar_badge_class("security"), do: "pbt-badge--critical"
  defp pillar_badge_class("x402"), do: "pbt-badge--amber"
  defp pillar_badge_class("mpp"), do: "pbt-badge--mpp"
  defp pillar_badge_class(_other), do: "pbt-badge--cobalt"

  defp rail_label("base:usdc"), do: "Base USDC"
  defp rail_label("tempo:usdc_e"), do: "Tempo USDC.e"
  defp rail_label("tempo:pathusd"), do: "Tempo pathUSD"
  defp rail_label("solana:usdc"), do: "Solana USDC"
  defp rail_label("stripe:link"), do: "Stripe Link"
  defp rail_label("free"), do: "Free"
  defp rail_label(other), do: other

  defp format_usdc(atomic) when is_integer(atomic) and atomic > 0 do
    whole = div(atomic, 1_000_000)
    cents = div(rem(atomic, 1_000_000), 10_000)
    "#{whole}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end

  defp format_usdc(_zero), do: "0.00"

  defp clean(val, max) when is_binary(val), do: val |> String.trim() |> String.slice(0, max)
  defp clean(_val, _max), do: ""
end
