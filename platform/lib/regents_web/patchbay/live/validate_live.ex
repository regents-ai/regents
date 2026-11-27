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
  alias Regents.Patchbay.Probes.{CryptoEndpoint, PaymentEndpoint}
  alias Regents.Patchbay.Security.{AuthorityInventory, CryptoAudit, StackCheck}
  alias RegentsWeb.Components.PostMath
  alias RegentsWeb.Patchbay.IncidentHTML

  @tabs ~w(endpoint sandboxes stack crypto)

  @sample_stacks %{
    "elixir" => "phoenix, plug, bandit, ash, ash_postgres, oban, req, idna, castore",
    "nextjs" =>
      ~s({"dependencies": {"next": "15.1.0", "react": "19.0.0", "viem": "2.21.0", "@modelcontextprotocol/sdk": "1.0.0"}}),
    "python" =>
      "fastapi==0.115.0\nlangchain==0.3.0\nlangflow==1.2.0\npydantic==2.9.0\nuvicorn==0.32.0"
  }

  @sample_crypto_stacks %{
    "elixir" => "erlang@29.1.2\nopenssl@3.5.0\nex_secp256k1@0.8.0\njose@1.11.13\nsiwa@0.1.0",
    "rust_cloak" =>
      ~s([dependencies]\nrustls = "0.23.46"\nring = "0.17.14"\ncurve25519-dalek = "4.1.3"\ndcap-qvl = "0.7.1"\nalloy = "2.1.0"),
    "python_cli" => "cryptography==50.0.2\neth-account==0.13.7\npyjwt==2.15.0\nckzg==2.1.0"
  }

  @sample_diffs %{
    "rust_cloak" => {
      ~s([dependencies]\nrustls = "0.23.46"\nring = "0.17.14"\ndcap-qvl = "0.7.1"),
      ~s([dependencies]\nrustls = "0.23.46"\naws-lc-rs = "1.19.0"\ndcap-qvl = "0.7.1")
    },
    "openssl_trixie" => {
      "erlang@29.1.2\nopenssl@3.0.15\ncryptography@43.0.1",
      "erlang@29.1.2\nopenssl@3.5.0\ncryptography@50.0.2"
    }
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
       stack_result: nil,
       crypto_url: "",
       crypto_probe_running?: false,
       crypto_probe_error: nil,
       crypto_probe_result: nil,
       crypto_input: "",
       crypto_audit_error: nil,
       crypto_audit_result: nil,
       diff_before: "",
       diff_after: "",
       diff_error: nil,
       diff_result: nil,
       authority_preset: "autolaunch_safe",
       authority_label: "Autolaunch Treasury Safe (3-of-5 Base)",
       authority_address: "0x1111111111111111111111111111111111111111",
       authority_chain_id: "8453",
       authority_classification: "supported_safe",
       authority_threshold: "3",
       authority_owners:
         "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n0xcccccccccccccccccccccccccccccccccccccccc\n0xdddddddddddddddddddddddddddddddddddddddd\n0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
       authority_exposed_owners: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
       authority_modules: "",
       authority_guard: "",
       authority_upgrade_admin: "",
       authority_recovery_mode: "human_multisig",
       authority_app_auth_coupled?: false,
       authority_error: nil,
       authority_result: nil
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

  def handle_event("prefill_crypto_probe", %{"url" => url}, socket) do
    {:noreply, assign(socket, tab: "crypto", crypto_url: url, crypto_probe_error: nil)}
  end

  def handle_event("run_crypto_probe", %{"url" => url}, socket) do
    url = String.trim(url || "")

    case Limits.spend(:patchbay_endpoint_probes, socket.assigns.visitor) do
      :ok ->
        {:noreply,
         socket
         |> assign(
           crypto_url: url,
           crypto_probe_running?: true,
           crypto_probe_error: nil,
           crypto_probe_result: nil
         )
         |> start_async(:crypto_probe, fn -> CryptoEndpoint.probe(url) end)}

      :limited ->
        {:noreply,
         assign(socket,
           crypto_url: url,
           crypto_probe_running?: false,
           crypto_probe_error: "Probe limit reached (20/minute). Wait a moment and try again."
         )}
    end
  end

  def handle_event("load_sample_crypto_stack", %{"sample" => key}, socket) do
    case Map.get(@sample_crypto_stacks, key) do
      nil -> {:noreply, socket}
      text -> {:noreply, assign(socket, crypto_input: text, crypto_audit_error: nil)}
    end
  end

  def handle_event("run_crypto_audit", %{"manifest" => manifest}, socket) do
    manifest = manifest || ""

    case Limits.spend(:patchbay_stack_checks, socket.assigns.visitor) do
      :ok ->
        case CryptoAudit.check(manifest) do
          {:ok, result} ->
            {:noreply,
             assign(socket,
               crypto_input: manifest,
               crypto_audit_error: nil,
               crypto_audit_result: result
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               crypto_input: manifest,
               crypto_audit_error: reason,
               crypto_audit_result: nil
             )}
        end

      :limited ->
        {:noreply,
         assign(socket,
           crypto_input: manifest,
           crypto_audit_error:
             "Stack check limit reached (60/minute). Wait a moment and try again."
         )}
    end
  end

  def handle_event("load_sample_diff", %{"sample" => key}, socket) do
    case Map.get(@sample_diffs, key) do
      {before_text, after_text} ->
        {:noreply,
         assign(socket, diff_before: before_text, diff_after: after_text, diff_error: nil)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("run_crypto_diff", %{"before" => before_text, "after" => after_text}, socket) do
    before_text = before_text || ""
    after_text = after_text || ""

    case Limits.spend(:patchbay_stack_checks, socket.assigns.visitor) do
      :ok ->
        case CryptoAudit.diff_audits(before_text, after_text) do
          {:ok, result} ->
            {:noreply,
             assign(socket,
               diff_before: before_text,
               diff_after: after_text,
               diff_error: nil,
               diff_result: result
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               diff_before: before_text,
               diff_after: after_text,
               diff_error: reason,
               diff_result: nil
             )}
        end

      :limited ->
        {:noreply,
         assign(socket,
           diff_before: before_text,
           diff_after: after_text,
           diff_error: "Stack check limit reached (60/minute). Wait a moment and try again."
         )}
    end
  end

  def handle_event("load_authority_preset", %{"preset" => key}, socket) do
    case AuthorityInventory.preset(key) do
      nil ->
        {:noreply, socket}

      cfg ->
        {:noreply,
         assign(socket,
           authority_preset: key,
           authority_label: cfg.label,
           authority_address: cfg.address,
           authority_chain_id: to_string(cfg.chain_id),
           authority_classification: cfg.classification,
           authority_threshold: to_string(cfg.threshold),
           authority_owners: Enum.join(cfg.owner_addresses, "\n"),
           authority_exposed_owners: Enum.join(cfg.exposed_owners, "\n"),
           authority_modules: Enum.join(cfg.modules, "\n"),
           authority_guard: cfg.guard || "",
           authority_upgrade_admin: cfg.upgrade_admin || "",
           authority_recovery_mode: cfg.recovery_mode,
           authority_app_auth_coupled?: cfg.app_auth_coupled?,
           authority_error: nil
         )}
    end
  end

  def handle_event("run_authority_check", params, socket) do
    case Limits.spend(:patchbay_stack_checks, socket.assigns.visitor) do
      :ok ->
        updated = assign_authority_form(socket, params)
        payload = authority_payload(params)

        case AuthorityInventory.analyze(payload) do
          {:ok, result} ->
            {:noreply, assign(updated, authority_error: nil, authority_result: result)}

          {:error, reason} ->
            {:noreply, assign(updated, authority_error: reason, authority_result: nil)}
        end

      :limited ->
        {:noreply,
         assign(socket,
           authority_error: "Stack check limit reached (60/minute). Wait a moment and try again."
         )}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp authority_payload(params) do
    %{
      "label" => params["label"],
      "address" => params["address"],
      "chain_id" => params["chain_id"],
      "classification" => params["classification"],
      "threshold" => params["threshold"],
      "owner_addresses" => params["owner_addresses"],
      "exposed_owners" => params["exposed_owners"],
      "modules" => params["modules"],
      "guard" => params["guard"],
      "upgrade_admin" => params["upgrade_admin"],
      "recovery_mode" => params["recovery_mode"],
      "app_auth_coupled" => params["app_auth_coupled"] in ["true", "on", "1"]
    }
  end

  defp assign_authority_form(socket, params) do
    assign(socket,
      authority_label: Map.get(params, "label", ""),
      authority_address: Map.get(params, "address", ""),
      authority_chain_id: Map.get(params, "chain_id", "8453"),
      authority_classification: Map.get(params, "classification", "supported_safe"),
      authority_threshold: Map.get(params, "threshold", "1"),
      authority_owners: Map.get(params, "owner_addresses", ""),
      authority_exposed_owners: Map.get(params, "exposed_owners", ""),
      authority_modules: Map.get(params, "modules", ""),
      authority_guard: Map.get(params, "guard", ""),
      authority_upgrade_admin: Map.get(params, "upgrade_admin", ""),
      authority_recovery_mode: Map.get(params, "recovery_mode", "human_multisig"),
      authority_app_auth_coupled?: params["app_auth_coupled"] in ["true", "on", "1"]
    )
  end

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

  def handle_async(:crypto_probe, {:ok, {:ok, result}}, socket) do
    {:noreply,
     assign(socket,
       crypto_probe_running?: false,
       crypto_probe_result: result,
       crypto_probe_error: nil
     )}
  end

  def handle_async(:crypto_probe, {:ok, {:error, reason}}, socket) do
    {:noreply,
     assign(socket,
       crypto_probe_running?: false,
       crypto_probe_result: nil,
       crypto_probe_error: reason
     )}
  end

  def handle_async(:crypto_probe, {:exit, _reason}, socket) do
    {:noreply,
     assign(socket,
       crypto_probe_running?: false,
       crypto_probe_result: nil,
       crypto_probe_error: "Crypto probe timed out or exited unexpectedly."
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
        <button
          type="button"
          role="tab"
          aria-selected={to_string(@tab == "crypto")}
          class={["pbt-tab", @tab == "crypto" && "is-active"]}
          phx-click="select_tab"
          phx-value-tab="crypto"
        >
          <PostMath.mark size={14} /> Post-Math &amp; Crypto Audit
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

      <%!-- TAB 4: CRYPTO & PQC AUDIT --%>
      <section :if={@tab == "crypto"} class="pbt-panel pbt-diag-body">
        <div class="pbt-stack-head">
          <div>
            <div class="pbt-post-math-head">
              <PostMath.badge
                state={:live}
                label="Post-Math · Live Verification"
                detail="Hybrid PQ TLS, downgrade checks, CycloneDX 1.6 CBOM diffs, and on-chain authority inventories."
              />
            </div>
            <h2>Live TLS, Hybrid PQ &amp; Downgrade Probe</h2>
            <p>
              Verify whether a public <code>https://</code>
              endpoint negotiates hybrid post-quantum key exchange (<code>X25519MLKEM768</code>), tolerates PQ ClientHellos without proxy drops, refuses forced TLS 1.2 classical downgrades, and check its certificate signature posture separately from transport confidentiality.
            </p>
          </div>
        </div>

        <form phx-submit="run_crypto_probe" class="pbt-probe-form">
          <input
            type="url"
            name="url"
            value={@crypto_url}
            placeholder="https://regents.sh"
            required
          />
          <button type="submit" class="pbt-btn pbt-btn--contrast" disabled={@crypto_probe_running?}>
            {if @crypto_probe_running?, do: "Probing TLS…", else: "Probe TLS & Certs"}
          </button>
        </form>

        <div class="pbt-preset-row">
          <span class="pbt-muted">Quick presets:</span>
          <button
            type="button"
            class="pbt-mini-pill pbt-mini-pill--btn"
            phx-click="prefill_crypto_probe"
            phx-value-url="https://regents.sh"
          >
            regents.sh
          </button>
          <button
            type="button"
            class="pbt-mini-pill pbt-mini-pill--btn"
            phx-click="prefill_crypto_probe"
            phx-value-url="https://siwa.regents.sh"
          >
            siwa.regents.sh
          </button>
          <button
            type="button"
            class="pbt-mini-pill pbt-mini-pill--btn"
            phx-click="prefill_crypto_probe"
            phx-value-url="https://cloudflare.com"
          >
            cloudflare.com
          </button>
        </div>

        <p :if={@crypto_probe_error} class="pbt-alert pbt-alert--critical" role="alert">
          {@crypto_probe_error}
        </p>

        <div :if={@crypto_probe_result} class="pbt-probe-result">
          <div class="pbt-probe-summary">
            <span class={["pbt-badge", verdict_badge(@crypto_probe_result.verdict)]}>
              {String.upcase(to_string(@crypto_probe_result.verdict))}
            </span>
            <span class="pbt-mono">
              {@crypto_probe_result.host}:{@crypto_probe_result.port} · {@crypto_probe_result.confidentiality.tls_protocol ||
                "TLS error"} · {@crypto_probe_result.latency_ms}ms
            </span>
            <div class="pbt-pill-group">
              <span class={[
                "pbt-badge",
                if(@crypto_probe_result.confidentiality.hybrid_pqc_negotiated?,
                  do: "pbt-badge--post-math",
                  else: "pbt-badge--amber"
                )
              ]}>
                KEX: {@crypto_probe_result.confidentiality.negotiated_pq_group || "Classical ECC"}
              </span>
              <span
                :if={@crypto_probe_result.downgrade.tested?}
                class={[
                  "pbt-badge",
                  if(@crypto_probe_result.downgrade.tls_1_2_accepted?,
                    do: "pbt-badge--amber",
                    else: "pbt-badge--good"
                  )
                ]}
              >
                {if @crypto_probe_result.downgrade.tls_1_2_accepted?,
                  do: "TLS 1.2 DOWNGRADE OPEN",
                  else: "TLS 1.3 ENFORCED"}
              </span>
              <span class={[
                "pbt-badge",
                if(@crypto_probe_result.authentication.pqc_certificate?,
                  do: "pbt-badge--good",
                  else: "pbt-badge--amber"
                )
              ]}>
                CERT: {(@crypto_probe_result.authentication.leaf_certificate &&
                          @crypto_probe_result.authentication.leaf_certificate.public_key_algorithm) ||
                  "Unknown"}
              </span>
            </div>
          </div>

          <ul class="pbt-check-list">
            <li
              :for={chk <- @crypto_probe_result.checks}
              class={"pbt-check-item pbt-check-item--" <> to_string(chk.level)}
            >
              <span class="pbt-badge">{String.upcase(to_string(chk.level))}</span>
              <span class="pbt-mono pbt-muted">{chk.code}</span>
              <span>{chk.message}</span>
            </li>
          </ul>

          <p class="pbt-muted pbt-mono">
            Verification digest: {@crypto_probe_result.verification_digest}
          </p>

          <div class="pbt-probe-actions">
            <a class="pbt-btn pbt-btn--primary" href={@crypto_probe_result.report_prefill.forum_url}>
              Report Finding on Patchbay →
            </a>
            <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/playbooks/ecc-pqc-migration-audit"}>
              Migration Playbook
            </a>
          </div>
        </div>

        <hr />

        <div class="pbt-stack-head">
          <div>
            <h2>Cryptographic Dependency &amp; CycloneDX 1.6 CBOM Audit</h2>
            <p>
              Paste <code>mix.lock</code>, <code>Cargo.toml</code>, <code>Cargo.lock</code>, <code>package-lock.json</code>, <code>uv.lock</code>, <code>go.mod</code>, or
              <code>name@version</code>
              lines to inventory ECC/RSA dependencies, distinguish app-owned upgrades from external chain or hardware rails, and generate a CycloneDX 1.6 CBOM.
            </p>
          </div>
          <div class="pbt-preset-row">
            <span class="pbt-muted">Samples:</span>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_sample_crypto_stack"
              phx-value-sample="elixir"
            >
              Elixir / SIWA
            </button>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_sample_crypto_stack"
              phx-value-sample="rust_cloak"
            >
              Rust / Cloak
            </button>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_sample_crypto_stack"
              phx-value-sample="python_cli"
            >
              Python / CLI
            </button>
          </div>
        </div>

        <form phx-submit="run_crypto_audit" class="pbt-stack-form">
          <textarea
            name="manifest"
            rows="6"
            placeholder="Paste Cargo.toml, mix.lock, package-lock.json, uv.lock, or runtime pins (e.g. openssl@3.0.15, rustls@0.23.46, ring@0.17.14)…"
          >{@crypto_input}</textarea>
          <div class="pbt-stack-form__foot">
            <span class="pbt-muted pbt-mono">
              API: POST /api/v1/patchbay/security/check-crypto · MCP: patchbay_check_crypto
            </span>
            <button type="submit" class="pbt-btn pbt-btn--contrast">Audit Crypto &amp; CBOM</button>
          </div>
        </form>

        <p :if={@crypto_audit_error} class="pbt-alert pbt-alert--critical" role="alert">
          {@crypto_audit_error}
        </p>

        <div :if={@crypto_audit_result} class="pbt-stack-result">
          <div class="pbt-probe-summary">
            <span class={[
              "pbt-badge",
              if(@crypto_audit_result.ecc_exposed_count == 0,
                do: "pbt-badge--good",
                else: "pbt-badge--amber"
              )
            ]}>
              {@crypto_audit_result.ecc_exposed_count} ECC/UPGRADE FINDING(S)
            </span>
            <span class="pbt-mono">
              Scanned {@crypto_audit_result.package_count} package(s) · {@crypto_audit_result.crypto_dependency_count} crypto dep(s) · {@crypto_audit_result.pqc_ready_count} PQC-ready · {@crypto_audit_result.external_rail_count} external rail(s)
            </span>
          </div>

          <div :if={@crypto_audit_result.ready_packages != []} class="pbt-related-fixes">
            <h3>PQC-Capable Dependencies ({@crypto_audit_result.pqc_ready_count})</h3>
            <div class="pbt-pill-group">
              <span :for={r <- @crypto_audit_result.ready_packages} class="pbt-badge pbt-badge--good">
                {r.package}{if r.installed_version, do: "@#{r.installed_version}", else: ""} · {Enum.join(
                  r.algorithms,
                  ", "
                )}
              </span>
            </div>
          </div>

          <div :if={@crypto_audit_result.findings != []} class="pbt-table-wrap">
            <table class="pbt-table">
              <thead>
                <tr>
                  <th>Dependency</th>
                  <th>Algorithms</th>
                  <th>Exposure &amp; Boundary</th>
                  <th>Recommended Action</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={f <- @crypto_audit_result.findings}>
                  <td>
                    <strong class="pbt-mono">
                      {f.package}{if f.installed_version, do: "@#{f.installed_version}", else: ""}
                    </strong>
                    <div class="pbt-muted">{f.ecosystem} · {f.role}</div>
                  </td>
                  <td>
                    <div class="pbt-pill-group">
                      <span :for={alg <- f.algorithms} class="pbt-mini-pill">{alg}</span>
                    </div>
                  </td>
                  <td>
                    <div class="pbt-pill-group">
                      <span class={[
                        "pbt-badge",
                        if(f.severity == "high", do: "pbt-badge--critical", else: "pbt-badge--amber")
                      ]}>
                        {f.exposure}
                      </span>
                      <span class="pbt-badge pbt-badge--cobalt">{f.boundary}</span>
                    </div>
                  </td>
                  <td>{f.remediation}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <p class="pbt-muted pbt-mono">
            Verification digest: {@crypto_audit_result.verification_digest}
          </p>

          <div :if={@crypto_audit_result[:cbom]} class="pbt-code-card">
            <h3>CycloneDX 1.6 CBOM (JSON)</h3>
            <pre><code>{Jason.encode!(@crypto_audit_result.cbom, pretty: true)}</code></pre>
          </div>
        </div>

        <hr />

        <div id="migration-diff" class="pbt-stack-head">
          <div>
            <h2>Before vs. After Migration Diff Receipt</h2>
            <p>
              Paste a pre-migration manifest beside a post-migration manifest to generate a reproducible
              <code>receipt_digest</code>
              proving ECC findings were resolved without introducing regressions.
            </p>
          </div>
          <div class="pbt-preset-row">
            <span class="pbt-muted">Diff presets:</span>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_sample_diff"
              phx-value-sample="rust_cloak"
            >
              Cloak: ring → aws-lc-rs
            </button>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_sample_diff"
              phx-value-sample="openssl_trixie"
            >
              OpenSSL 3.0 → 3.5 + Py 50
            </button>
          </div>
        </div>

        <form phx-submit="run_crypto_diff" class="pbt-stack-form">
          <div class="pbt-diff-grid">
            <label>
              <span class="pbt-muted pbt-mono">Before manifest</span>
              <textarea
                name="before"
                rows="5"
                placeholder="Before migration (e.g. rustls@0.23.46, ring@0.17.14)…"
              >{@diff_before}</textarea>
            </label>
            <label>
              <span class="pbt-muted pbt-mono">After manifest</span>
              <textarea
                name="after"
                rows="5"
                placeholder="After migration (e.g. rustls@0.23.46, aws-lc-rs@1.19.0)…"
              >{@diff_after}</textarea>
            </label>
          </div>
          <div class="pbt-stack-form__foot">
            <span class="pbt-muted pbt-mono">
              API: POST /api/v1/patchbay/security/diff-crypto · MCP: patchbay_diff_crypto
            </span>
            <button type="submit" class="pbt-btn pbt-btn--contrast">
              Generate Migration Receipt
            </button>
          </div>
        </form>

        <p :if={@diff_error} class="pbt-alert pbt-alert--critical" role="alert">{@diff_error}</p>

        <div :if={@diff_result} class="pbt-stack-result">
          <div class="pbt-probe-summary">
            <span class={[
              "pbt-badge",
              if(@diff_result.migration_verified?,
                do: "pbt-badge--post-math",
                else: "pbt-badge--amber"
              )
            ]}>
              {if @diff_result.migration_verified?,
                do: "MIGRATION VERIFIED",
                else: String.upcase(@diff_result.status)}
            </span>
            <span class="pbt-mono">
              ECC findings: {@diff_result.ecc_exposed_before} → {@diff_result.ecc_exposed_after} · PQC-ready: {@diff_result.pqc_ready_before} → {@diff_result.pqc_ready_after}
            </span>
          </div>

          <div :if={@diff_result.resolved_findings != []} class="pbt-related-fixes">
            <h3>Resolved Findings ({length(@diff_result.resolved_findings)})</h3>
            <div class="pbt-pill-group">
              <span :for={item <- @diff_result.resolved_findings} class="pbt-badge pbt-badge--good">
                {item.package}{if item.version, do: "@#{item.version}", else: ""} resolved
              </span>
            </div>
          </div>

          <div :if={@diff_result.newly_pqc_ready != []} class="pbt-related-fixes">
            <h3>Newly PQC-Capable ({length(@diff_result.newly_pqc_ready)})</h3>
            <div class="pbt-pill-group">
              <span
                :for={item <- @diff_result.newly_pqc_ready}
                class="pbt-badge pbt-badge--post-math"
              >
                {item.package}{if item.version, do: "@#{item.version}", else: ""} · {Enum.join(
                  item.algorithms,
                  ", "
                )}
              </span>
            </div>
          </div>

          <div :if={@diff_result.new_findings != []} class="pbt-related-fixes">
            <h3>New Regressions ({length(@diff_result.new_findings)})</h3>
            <div class="pbt-pill-group">
              <span :for={item <- @diff_result.new_findings} class="pbt-badge pbt-badge--critical">
                {item.package} ({item.status})
              </span>
            </div>
          </div>

          <p class="pbt-muted pbt-mono">
            Receipt digest: {@diff_result.receipt_digest} · Before: {@diff_result.before_digest} · After: {@diff_result.after_digest}
          </p>
        </div>

        <hr />

        <div id="authority-inventory" class="pbt-stack-head">
          <div>
            <h2>On-Chain Authority Exposure Inventory (&ldquo;Embedded Firmware&rdquo; Check)</h2>
            <p>
              Audit a Safe multisig, Autolaunch treasury, Keyfleet fleet contract, or EOA admin to separate mutable contract controls from immutable Base/EVM L1
              <code>secp256k1</code>
              boundaries and check whether exposed owner keys can reach execution quorum.
            </p>
          </div>
          <div class="pbt-preset-row">
            <span class="pbt-muted">Presets:</span>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_authority_preset"
              phx-value-preset="autolaunch_safe"
            >
              Autolaunch Safe (3-of-5)
            </button>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_authority_preset"
              phx-value-preset="keyfleet_treasury"
            >
              Keyfleet Treasury
            </button>
            <button
              type="button"
              class="pbt-mini-pill pbt-mini-pill--btn"
              phx-click="load_authority_preset"
              phx-value-preset="single_eoa_admin"
            >
              Single Hot EOA
            </button>
          </div>
        </div>

        <form phx-submit="run_authority_check" class="pbt-stack-form">
          <div class="pbt-diff-grid">
            <label>
              <span class="pbt-muted pbt-mono">Label</span>
              <input type="text" name="label" value={@authority_label} />
            </label>
            <label>
              <span class="pbt-muted pbt-mono">Contract / Treasury Address (optional)</span>
              <input type="text" name="address" value={@authority_address} placeholder="0x…" />
            </label>
            <label>
              <span class="pbt-muted pbt-mono">Classification</span>
              <span class="rg-select pbt-select">
                <select name="classification">
                  <option
                    value="supported_safe"
                    selected={@authority_classification == "supported_safe"}
                  >
                    supported_safe (Multisig Safe)
                  </option>
                  <option value="safe_1_of_1" selected={@authority_classification == "safe_1_of_1"}>
                    safe_1_of_1 (1-of-1 Safe)
                  </option>
                  <option value="eoa" selected={@authority_classification == "eoa"}>
                    eoa (Single EOA)
                  </option>
                  <option
                    value="delegated_eoa"
                    selected={@authority_classification == "delegated_eoa"}
                  >
                    delegated_eoa (EIP-7702 EOA)
                  </option>
                  <option
                    value="unknown_contract"
                    selected={@authority_classification == "unknown_contract"}
                  >
                    unknown_contract
                  </option>
                  <option value="split" selected={@authority_classification == "split"}>
                    split
                  </option>
                </select>
              </span>
            </label>
            <label>
              <span class="pbt-muted pbt-mono">Threshold &amp; Chain ID</span>
              <div class="pbt-diff-grid">
                <input
                  type="number"
                  min="0"
                  name="threshold"
                  value={@authority_threshold}
                  aria-label="Signing threshold"
                />
                <input
                  type="number"
                  min="1"
                  name="chain_id"
                  value={@authority_chain_id}
                  aria-label="Chain ID"
                />
              </div>
            </label>
            <label>
              <span class="pbt-muted pbt-mono">Owner Addresses (one per line)</span>
              <textarea name="owner_addresses" rows="4">{@authority_owners}</textarea>
            </label>
            <label>
              <span class="pbt-muted pbt-mono">
                Exposed Owners (signed on-chain / hot keys)
              </span>
              <textarea name="exposed_owners" rows="4">{@authority_exposed_owners}</textarea>
            </label>
            <label>
              <span class="pbt-muted pbt-mono">Safe Modules (optional, one per line)</span>
              <textarea name="modules" rows="2">{@authority_modules}</textarea>
            </label>
            <label>
              <span class="pbt-muted pbt-mono">Out-of-Band Recovery Mode</span>
              <span class="rg-select pbt-select">
                <select name="recovery_mode">
                  <option
                    value="human_multisig"
                    selected={@authority_recovery_mode == "human_multisig"}
                  >
                    human_multisig
                  </option>
                  <option
                    value="timelock_guardian"
                    selected={@authority_recovery_mode == "timelock_guardian"}
                  >
                    timelock_guardian
                  </option>
                  <option value="none" selected={@authority_recovery_mode == "none"}>
                    none
                  </option>
                </select>
              </span>
            </label>
            <label>
              <span class="pbt-muted pbt-mono">Safe Guard Address (optional)</span>
              <input type="text" name="guard" value={@authority_guard} placeholder="0x…" />
            </label>
            <label>
              <span class="pbt-muted pbt-mono">Upgrade Admin Address (optional)</span>
              <input
                type="text"
                name="upgrade_admin"
                value={@authority_upgrade_admin}
                placeholder="0x…"
              />
            </label>
          </div>
          <label class="pbt-muted">
            <input
              type="checkbox"
              name="app_auth_coupled"
              value="true"
              checked={@authority_app_auth_coupled?}
            /> Off-chain agent auth (SIWA / API) shares keys with this treasury
          </label>
          <div class="pbt-stack-form__foot">
            <span class="pbt-muted pbt-mono">
              API: POST /api/v1/patchbay/security/check-authority · MCP: patchbay_check_authority
            </span>
            <button type="submit" class="pbt-btn pbt-btn--contrast">
              Analyze Authority Exposure
            </button>
          </div>
        </form>

        <p :if={@authority_error} class="pbt-alert pbt-alert--critical" role="alert">
          {@authority_error}
        </p>

        <div :if={@authority_result} class="pbt-stack-result">
          <div class="pbt-probe-summary">
            <span class={["pbt-badge", verdict_badge(@authority_result.verdict)]}>
              {String.upcase(to_string(@authority_result.verdict))}
            </span>
            <span class="pbt-mono">
              {@authority_result.label} · chain {@authority_result.chain_id} · {@authority_result.quorum_posture.threshold}-of-{@authority_result.quorum_posture.owner_count} · {@authority_result.quorum_posture.exposed_owner_count} exposed · {@authority_result.quorum_posture.unexposed_owner_count} unexposed
            </span>
          </div>

          <ul class="pbt-check-list">
            <li
              :for={chk <- @authority_result.checks}
              class={"pbt-check-item pbt-check-item--" <> to_string(chk.level)}
            >
              <span class="pbt-badge">{String.upcase(to_string(chk.level))}</span>
              <span class="pbt-mono pbt-muted">{chk.code}</span>
              <span>{chk.message}</span>
            </li>
          </ul>

          <div class="pbt-table-wrap">
            <table class="pbt-table">
              <thead>
                <tr>
                  <th>Authority Surface</th>
                  <th>Boundary</th>
                  <th>Algorithm</th>
                  <th>Migration Note</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={s <- @authority_result.surfaces}>
                  <td><strong>{s.surface}</strong></td>
                  <td>
                    <span class={[
                      "pbt-badge",
                      if(s.boundary == "mutable_in_contract",
                        do: "pbt-badge--post-math",
                        else: "pbt-badge--cobalt"
                      )
                    ]}>
                      {s.boundary}
                    </span>
                  </td>
                  <td class="pbt-mono">{s.algorithm}</td>
                  <td>{s.note}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="pbt-related-fixes">
            <h3>Rotation &amp; Containment Rehearsal Steps</h3>
            <ul class="pbt-check-list">
              <li :for={step <- @authority_result.rehearsal_steps} class="pbt-check-item">
                <span>{step}</span>
              </li>
            </ul>
          </div>

          <p class="pbt-muted pbt-mono">
            Verification digest: {@authority_result.verification_digest}
          </p>
        </div>
      </section>
    </div>
    """
  end

  defp verdict_badge(:pass), do: "pbt-badge--good"
  defp verdict_badge(:warn), do: "pbt-badge--amber"
  defp verdict_badge(_fail), do: "pbt-badge--critical"
end
