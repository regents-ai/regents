defmodule RegentsWeb.Patchbay.ValidateLive do
  @moduledoc """
  Interactive Protocol & Security Diagnostics at `/patchbay/validate`, modeled on
  `agentic.market/validate` and tailored to Patchbay's four pillars:
  1. **Endpoint 402 Validator** — Live SSRF-safe probe inspecting x402 v2
     (`PAYMENT-REQUIRED`, Bazaar metadata, CORS) and MPP (`WWW-Authenticate: Payment`
     for Tempo & Stripe).
  2. **Live Payment & Auth Sandboxes** — Interactive testbed for `/patchbay/bench/x402-test`
     (Base USDC), `/patchbay/bench/mpp-test` (Tempo `USDC.e` charge & session), and
     `/patchbay/siwa-test`.
  3. **Stack CVE Check (`cve.now`)** — Paste `package.json`, `mix.lock`, `requirements.txt`,
     `Cargo.toml`, `go.mod`, or package names to check active criticals joined with
     Patchbay mitigation threads.
  """

  use RegentsWeb, :live_view

  alias Regents.Limits
  alias Regents.Patchbay.Assist.KnownFixes
  alias Regents.Patchbay.Probes.PaymentEndpoint
  alias Regents.Patchbay.Security.StackCheck
  alias RegentsWeb.Patchbay.IncidentHTML

  @tabs ~w(endpoint sandboxes stack)

  @sample_stacks %{
    "elixir" => "phoenix, plug, bandit, ash, ash_postgres, oban, req, idna, castore",
    "nextjs" =>
      ~s({"dependencies": {"next": "15.1.0", "react": "19.0.0", "viem": "2.21.0", "@modelcontextprotocol/sdk": "1.0.0"}}),
    "python" =>
      "fastapi==0.115.0\nlangchain==0.3.0\nlangflow==1.2.0\npydantic==2.9.0\nuvicorn==0.32.0"
  }

  @impl true
  def mount(_params, session, socket) do
    origin = RegentsWeb.Endpoint.url()

    {:ok,
     socket
     |> assign(RegentsWeb.Patchbay.PublicDocuments.page("/patchbay/validate"))
     |> assign(
       visitor: session["client_tag"] || "anon",
       origin: origin,
       tab: "endpoint",
       url: "",
       method: "GET",
       probe_running?: false,
       probe_error: nil,
       probe_result: nil,
       stack_input: "",
       stack_error: nil,
       stack_result: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "endpoint"
    url = if is_binary(params["url"]), do: String.trim(params["url"]), else: socket.assigns.url

    method =
      if params["method"] in ~w(GET POST HEAD), do: params["method"], else: socket.assigns.method

    {:noreply, assign(socket, tab: tab, url: url, method: method)}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, push_patch(socket, to: ~p"/patchbay/validate?#{[tab: tab]}")}
  end

  def handle_event("prefill_probe", %{"url" => url} = params, socket) do
    method = if params["method"] in ~w(GET POST HEAD), do: params["method"], else: "GET"
    {:noreply, assign(socket, tab: "endpoint", url: url, method: method, probe_error: nil)}
  end

  def handle_event("run_probe", %{"url" => url, "method" => method}, socket) do
    url = String.trim(url || "")
    method = if method in ~w(GET POST HEAD), do: method, else: "GET"

    case Limits.spend(:patchbay_endpoint_probes, socket.assigns.visitor) do
      :ok ->
        {:noreply,
         socket
         |> assign(
           url: url,
           method: method,
           probe_running?: true,
           probe_error: nil,
           probe_result: nil
         )
         |> start_async(:probe, fn -> PaymentEndpoint.probe(url, method) end)}

      :limited ->
        {:noreply,
         assign(socket,
           url: url,
           method: method,
           probe_running?: false,
           probe_error: "Probe limit reached (20/minute). Wait a moment and try again."
         )}
    end
  end

  def handle_event("load_sample_stack", %{"sample" => key}, socket) do
    case Map.get(@sample_stacks, key) do
      nil -> {:noreply, socket}
      text -> {:noreply, assign(socket, stack_input: text, stack_error: nil)}
    end
  end

  def handle_event("run_stack_check", %{"manifest" => manifest}, socket) do
    manifest = manifest || ""

    case Limits.spend(:patchbay_stack_checks, socket.assigns.visitor) do
      :ok ->
        case StackCheck.check(manifest) do
          {:ok, result} ->
            {:noreply,
             assign(socket, stack_input: manifest, stack_error: nil, stack_result: result)}

          {:error, reason} ->
            {:noreply,
             assign(socket, stack_input: manifest, stack_error: reason, stack_result: nil)}
        end

      :limited ->
        {:noreply,
         assign(socket,
           stack_input: manifest,
           stack_error: "Stack check limit reached (60/minute). Wait a moment and try again."
         )}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:probe, {:ok, {:ok, result}}, socket) do
    {:noreply, assign(socket, probe_running?: false, probe_result: result, probe_error: nil)}
  end

  def handle_async(:probe, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, probe_running?: false, probe_result: nil, probe_error: reason)}
  end

  def handle_async(:probe, {:exit, _reason}, socket) do
    {:noreply,
     assign(socket,
       probe_running?: false,
       probe_result: nil,
       probe_error: "Endpoint probe timed out or exited unexpectedly."
     )}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div id="pb-validate" class="pbt-shell">
      <header class="pbt-subpage-head">
        <div>
          <span class="pbt-eyebrow">PATCHBAY DIAGNOSTICS & SELLER TOOLS</span>
          <h1>Validate x402, MPP (Tempo) & Stack Security</h1>
          <p>
            Probe any public <code>https://</code>
            endpoint for HTTP 402 protocol compliance, test your agent wallet against live Base and Tempo sandboxes, or check dependencies against live
            <code>cve.now</code>
            active criticals.
          </p>
        </div>
        <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/app"}>← Back to Terminal</a>
      </header>

      <div class="pbt-tabs" role="tablist" aria-label="Diagnostic tools">
        <button
          type="button"
          role="tab"
          aria-selected={to_string(@tab == "endpoint")}
          class={["pbt-tab", @tab == "endpoint" && "is-active"]}
          phx-click="select_tab"
          phx-value-tab="endpoint"
        >
          Endpoint 402 Validator
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={to_string(@tab == "sandboxes")}
          class={["pbt-tab", @tab == "sandboxes" && "is-active"]}
          phx-click="select_tab"
          phx-value-tab="sandboxes"
        >
          Live Sandboxes (x402 & MPP Tempo)
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={to_string(@tab == "stack")}
          class={["pbt-tab", @tab == "stack" && "is-active"]}
          phx-click="select_tab"
          phx-value-tab="stack"
        >
          Stack CVE Check (cve.now)
        </button>
      </div>

      <%!-- TAB 1: ENDPOINT 402 VALIDATOR --%>
      <section :if={@tab == "endpoint"} class="pbt-panel pbt-diag-body">
        <form phx-submit="run_probe" class="pbt-probe-form">
          <span class="rg-select pbt-select">
            <select name="method" aria-label="HTTP method">
              <option value="GET" selected={@method == "GET"}>GET</option>
              <option value="POST" selected={@method == "POST"}>POST</option>
              <option value="HEAD" selected={@method == "HEAD"}>HEAD</option>
            </select>
          </span>
          <input
            type="url"
            name="url"
            value={@url}
            placeholder="https://api.example.com/v1/search"
            required
          />
          <button type="submit" class="pbt-btn pbt-btn--contrast" disabled={@probe_running?}>
            {if @probe_running?, do: "Probing…", else: "Validate Endpoint"}
          </button>
        </form>

        <div class="pbt-preset-row">
          <span class="pbt-muted">Quick presets:</span>
          <button
            type="button"
            class="pbt-mini-pill pbt-mini-pill--btn"
            phx-click="prefill_probe"
            phx-value-url="https://regents.sh/patchbay/bench/x402-test"
            phx-value-method="GET"
          >
            Patchbay x402 (Base USDC)
          </button>
          <button
            type="button"
            class="pbt-mini-pill pbt-mini-pill--btn"
            phx-click="prefill_probe"
            phx-value-url="https://regents.sh/patchbay/bench/mpp-test"
            phx-value-method="GET"
          >
            Patchbay MPP (Tempo Charge)
          </button>
          <button
            type="button"
            class="pbt-mini-pill pbt-mini-pill--btn"
            phx-click="prefill_probe"
            phx-value-url="https://regents.sh/patchbay/bench/mpp-test?intent=session"
            phx-value-method="GET"
          >
            Patchbay MPP (Tempo Session)
          </button>
        </div>

        <p :if={@probe_error} class="pbt-alert pbt-alert--critical" role="alert">
          {@probe_error}
        </p>

        <div :if={@probe_result} class="pbt-probe-result">
          <div class="pbt-probe-summary">
            <span class={["pbt-badge", verdict_badge(@probe_result.verdict)]}>
              {String.upcase(to_string(@probe_result.verdict))}
            </span>
            <span class="pbt-mono">
              {@probe_result.method} {@probe_result.url} → HTTP {@probe_result.status} ({@probe_result.latency_ms}ms)
            </span>
            <div class="pbt-pill-group">
              <span
                :for={proto <- @probe_result.detected_protocols}
                class={[
                  "pbt-badge",
                  if(proto == "x402", do: "pbt-badge--amber", else: "pbt-badge--mpp")
                ]}
              >
                {String.upcase(proto)}
              </span>
            </div>
          </div>

          <ul class="pbt-check-list">
            <li
              :for={chk <- @probe_result.checks}
              class={"pbt-check-item pbt-check-item--" <> to_string(chk.level)}
            >
              <span class="pbt-badge">{String.upcase(to_string(chk.level))}</span>
              <span class="pbt-mono pbt-muted">{chk.code}</span>
              <span>{chk.message}</span>
            </li>
          </ul>

          <div class="pbt-diag-grid">
            <div :if={@probe_result.x402.present?} class="pbt-code-card">
              <h3>Decoded x402 Challenge</h3>
              <pre><code>{Jason.encode!(@probe_result.x402, pretty: true)}</code></pre>
            </div>
            <div :if={@probe_result.mpp.present?} class="pbt-code-card">
              <h3>Decoded MPP (WWW-Authenticate: Payment)</h3>
              <pre><code>{Jason.encode!(@probe_result.mpp, pretty: true)}</code></pre>
            </div>
          </div>

          <div :if={@probe_result.known_fix_ids != []} class="pbt-related-fixes">
            <h3>Matching Patchbay Known Fixes</h3>
            <div class="pbt-pill-group">
              <a
                :for={fix_id <- @probe_result.known_fix_ids}
                :if={KnownFixes.get(fix_id)}
                href={"/patchbay/known-fixes/#{fix_id}"}
                class="pbt-link-pill"
              >
                {KnownFixes.get(fix_id).title} →
              </a>
            </div>
          </div>

          <div class="pbt-probe-actions">
            <a
              class="pbt-btn pbt-btn--primary"
              href={@probe_result.report_prefill.forum_url}
            >
              {if @probe_result.verdict == :pass,
                do: "Share Note on Patchbay →",
                else: "Report Failure on Patchbay (Prefilled Wire Trace) →"}
            </a>
          </div>
        </div>
      </section>

      <%!-- TAB 2: LIVE SANDBOXES --%>
      <section :if={@tab == "sandboxes"} class="pbt-sandbox-grid">
        <article class="pbt-panel pbt-sandbox-card">
          <div class="pbt-sandbox-card__top">
            <span class="pbt-badge pbt-badge--amber">x402 v2 · BASE MAINNET</span>
            <span class="pbt-mono">$0.01 USDC</span>
          </div>
          <h2>x402 Paid-Call Sandbox</h2>
          <p>
            Official Wallet Bench x402 v2 exact EVM endpoint settled on Base (<code>eip155:8453</code>). Returns a real
            <code>PAYMENT-REQUIRED</code>
            header on unpaid requests and <code>{"{\"message\":\"test passed\"}"}</code>
            once settled.
          </p>
          <pre class="pbt-code-snippet"><code>curl -i {@origin}/patchbay/bench/x402-test</code></pre>
          <div class="pbt-pill-group">
            <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/playbooks/debug-x402-http-402"}>
              x402 Debug Playbook
            </a>
            <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/wallet-bench"}>
              See Wallet Bench
            </a>
          </div>
        </article>

        <article class="pbt-panel pbt-sandbox-card">
          <div class="pbt-sandbox-card__top">
            <span class="pbt-badge pbt-badge--mpp">MPP · TEMPO NETWORK</span>
            <span class="pbt-mono">$0.01 USDC.e</span>
          </div>
          <h2>MPP (Tempo) Charge & Session Sandbox</h2>
          <p>
            Emits a compliant <code>HTTP 402</code>
            + <code>WWW-Authenticate: Payment</code>
            challenge (<code>method="tempo"</code>, <code>eip155:4217</code>) supporting both one-shot
            <code>charge</code>
            and metered <code>?intent=session</code>
            flows, plus structural validation of <code>Authorization: Payment</code>
            credentials.
          </p>
          <pre class="pbt-code-snippet"><code>curl -i {@origin}/patchbay/bench/mpp-test
    curl -i "{@origin}/patchbay/bench/mpp-test?intent=session"</code></pre>
          <div class="pbt-pill-group">
            <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/playbooks/debug-mpp-tempo-sessions"}>
              MPP Tempo Playbook
            </a>
          </div>
        </article>

        <article class="pbt-panel pbt-sandbox-card">
          <div class="pbt-sandbox-card__top">
            <span class="pbt-badge pbt-badge--cobalt">SIWA · AGENT IDENTITY</span>
            <span class="pbt-mono">Free</span>
          </div>
          <h2>SIWA Signed-Request Probe</h2>
          <p>
            Verify your agent's SIWA signature headers and Regents pairing status against a read-only diagnostic endpoint without mutating any state.
          </p>
          <pre class="pbt-code-snippet"><code>curl -i {@origin}/patchbay/siwa-test</code></pre>
          <div class="pbt-pill-group">
            <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/start"}>Pair Agent Guide</a>
          </div>
        </article>
      </section>

      <%!-- TAB 3: STACK CVE CHECK (cve.now) --%>
      <section :if={@tab == "stack"} class="pbt-panel pbt-diag-body">
        <div class="pbt-stack-head">
          <div>
            <h2>Stack Vulnerability Check (<code>cve.now</code> Active Criticals)</h2>
            <p>
              Paste <code>package.json</code>, <code>mix.lock</code>, <code>requirements.txt</code>, <code>Cargo.toml</code>, <code>go.mod</code>, or package names. Patchbay matches them against live mirrored
              <code>cve.now</code>
              critical & CISA KEV vulnerabilities and surfaces community mitigations.
            </p>
          </div>
          <div class="pbt-preset-row">
            <span class="pbt-muted">Samples:</span>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_sample_stack"
              phx-value-sample="elixir"
            >
              Elixir / Phoenix
            </button>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_sample_stack"
              phx-value-sample="nextjs"
            >
              Next.js + MCP
            </button>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_sample_stack"
              phx-value-sample="python"
            >
              Python Agent Stack
            </button>
          </div>
        </div>

        <form phx-submit="run_stack_check" class="pbt-stack-form">
          <textarea
            name="manifest"
            rows="6"
            placeholder="Paste package.json, mix.lock, requirements.txt, or comma-separated packages (e.g. next, plug, langflow, openssl)…"
          >{@stack_input}</textarea>
          <div class="pbt-stack-form__foot">
            <span class="pbt-muted pbt-mono">
              API: POST /api/v1/patchbay/security/check-stack · MCP: patchbay_check_stack
            </span>
            <button type="submit" class="pbt-btn pbt-btn--contrast">Scan Active Criticals</button>
          </div>
        </form>

        <p :if={@stack_error} class="pbt-alert pbt-alert--critical" role="alert">{@stack_error}</p>

        <div :if={@stack_result} class="pbt-stack-result">
          <div class="pbt-probe-summary">
            <span class={[
              "pbt-badge",
              if(@stack_result.match_count == 0, do: "pbt-badge--good", else: "pbt-badge--critical")
            ]}>
              {if @stack_result.match_count == 0,
                do: "NO ACTIVE CRITICAL MATCHES",
                else: "#{@stack_result.match_count} MATCH(ES)"}
            </span>
            <span class="pbt-mono">
              Checked {@stack_result.package_count} package(s) ({@stack_result.versioned_package_count} version-pinned) against {@stack_result.cves_scanned} mirrored cve.now criticals
              · {@stack_result.kev_match_count} KEV · {@stack_result.unfixed_match_count} unfixed
              · {@stack_result.cleared_count} patched pin(s) cleared
            </span>
          </div>

          <div :if={@stack_result.cleared_count > 0} class="pbt-related-fixes">
            <h3>Cleared as Patched ({@stack_result.cleared_count})</h3>
            <div class="pbt-pill-group">
              <span :for={c <- @stack_result.cleared_packages} class="pbt-badge pbt-badge--good">
                {c.package}@{c.installed_version} safe vs {c.cve_id}
              </span>
            </div>
          </div>

          <div :if={@stack_result.matches != []} class="pbt-table-wrap">
            <table class="pbt-table">
              <thead>
                <tr>
                  <th>Advisory</th>
                  <th>Matched Packages</th>
                  <th>Severity / KEV</th>
                  <th>Fix Status</th>
                  <th>Patchbay Thread</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={m <- @stack_result.matches}>
                  <td>
                    <a href={m.patchbay_path} class="pbt-svc-cell">
                      <strong class="pbt-mono">{m.id}</strong>
                      <span>{m.title}</span>
                    </a>
                  </td>
                  <td>
                    <div class="pbt-pill-group">
                      <span :for={pkg <- m.matched_packages} class="pbt-mini-pill">{pkg}</span>
                    </div>
                  </td>
                  <td>
                    <div class="pbt-pill-group">
                      <span :if={m.exploited} class="pbt-badge pbt-badge--critical">KEV</span>
                      <span :if={m.score} class="pbt-badge pbt-badge--amber">
                        CVSS {IncidentHTML.score_text(m.score)}
                      </span>
                    </div>
                  </td>
                  <td>
                    <span :if={m.fix_available} class="pbt-badge pbt-badge--good">FIX OUT</span>
                    <span :if={!m.fix_available} class="pbt-badge pbt-badge--critical">NO FIX YET</span>
                  </td>
                  <td>
                    <a href={m.patchbay_path} class="pbt-row-link">
                      Open mitigations ({m.reply_count}) →
                    </a>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp verdict_badge(:pass), do: "pbt-badge--good"
  defp verdict_badge(:warn), do: "pbt-badge--amber"
  defp verdict_badge(_fail), do: "pbt-badge--critical"
end
