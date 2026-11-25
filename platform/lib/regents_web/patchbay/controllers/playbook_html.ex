defmodule RegentsWeb.Patchbay.PlaybookHTML do
  @moduledoc "HTML templates for Patchbay Agent Support Playbooks."

  use RegentsWeb, :html

  def index(assigns) do
    ~H"""
    <div class="pbt-shell">
      <header class="pbt-subpage-head">
        <div>
          <span class="pbt-eyebrow">AGENT SUPPORT PLAYBOOKS</span>
          <h1>Composable Prompts for Commerce & Security</h1>
          <p>
            Copyable multi-step agent prompts and verification checklists covering x402, MPP (Tempo), Agentic Commerce, and live
            <code>cve.now</code>
            critical CVE triage.
          </p>
        </div>
        <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/app"}>← Back to Terminal</a>
      </header>

      <div class="pbt-playbook-grid">
        <a :for={pb <- @playbooks} href={"/patchbay/playbooks/#{pb.slug}"} class="pbt-playbook-card">
          <div class="pbt-playbook-card__top">
            <span class="pbt-badge pbt-badge--cobalt">{String.upcase(pb.pillar)}</span>
            <span class="pbt-playbook-card__cost">{pb.estimated_cost}</span>
          </div>
          <h2>{pb.title}</h2>
          <p>{pb.summary}</p>
          <div class="pbt-playbook-card__pills">
            <span :for={proto <- pb.protocols} class="pbt-mini-pill">{proto}</span>
          </div>
          <div class="pbt-playbook-card__foot">Open playbook →</div>
        </a>
      </div>
    </div>
    """
  end

  def show(assigns) do
    ~H"""
    <div class="pbt-shell">
      <nav class="pbt-breadcrumb" aria-label="Breadcrumb">
        <a href={~p"/patchbay/app"}>PATCHBAY</a>
        <span>/</span>
        <a href={~p"/patchbay/playbooks"}>PLAYBOOKS</a>
        <span>/</span>
        <span>{String.upcase(@playbook.slug)}</span>
      </nav>

      <div class="pbt-playbook-layout">
        <main class="pbt-panel pbt-playbook-main">
          <div class="pbt-playbook-card__top">
            <span class="pbt-badge pbt-badge--cobalt">{String.upcase(@playbook.pillar)}</span>
            <a class="pbt-row-link" href={"/patchbay/playbooks/#{@playbook.slug}.md"}>
              View Markdown (.md)
            </a>
          </div>
          <h1>{@playbook.title}</h1>
          <p class="pbt-playbook-lead">{@playbook.summary}</p>
          <p :if={@playbook.objective != ""}>
            <.inline_code text={@playbook.objective} />
          </p>

          <section class="pbt-prompt-box">
            <div class="pbt-prompt-box__head">
              <div>
                <span>AGENT PROMPT</span>
                <span class="pbt-mono pbt-muted">
                  · Paste directly into Claude Code, Codex, Hermes, or Cursor
                </span>
              </div>
              <button
                type="button"
                class="rg-copy pbt-btn pbt-btn--contrast pbt-btn--sm"
                data-copy-target="pbt-playbook-prompt"
              >
                Copy prompt
              </button>
            </div>
            <pre id="pbt-playbook-prompt"><code>{@playbook.prompt}</code></pre>
          </section>

          <section :if={@playbook.checks != []} class="pbt-checks-box">
            <h2>Included Patchbay Tools & Checks</h2>
            <ul>
              <li :for={line <- @playbook.checks}>
                <.inline_code text={line} />
              </li>
            </ul>
          </section>
        </main>

        <aside class="pbt-playbook-side">
          <div class="pbt-panel pbt-snapshot-card">
            <h2>Snapshot</h2>
            <dl class="pbt-kv">
              <div>
                <dt>ESTIMATED COST</dt>
                <dd class="pbt-mono">{@playbook.estimated_cost}</dd>
              </div>
              <div>
                <dt>PILLAR</dt>
                <dd class="pbt-mono">{String.upcase(@playbook.pillar)}</dd>
              </div>
              <div>
                <dt>PROTOCOLS</dt>
                <dd class="pbt-pill-group">
                  <span :for={p <- @playbook.protocols} class="pbt-mini-pill">{p}</span>
                </dd>
              </div>
              <div>
                <dt>SERVICES IN PLAYBOOK</dt>
                <dd class="pbt-pill-group">
                  <span :for={s <- @playbook.services} class="pbt-mini-pill">{s}</span>
                </dd>
              </div>
            </dl>
            <div class="pbt-snapshot-actions">
              <a class="pbt-btn pbt-btn--contrast" href={~p"/patchbay/validate"}>
                Open Live Validator →
              </a>
              <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/app"}>
                Return to Terminal
              </a>
            </div>
          </div>

          <div :if={@others != []} class="pbt-panel pbt-snapshot-card">
            <h2>Other Playbooks</h2>
            <ul class="pbt-side-links">
              <li :for={pb <- @others}>
                <a href={"/patchbay/playbooks/#{pb.slug}"}>{pb.title} →</a>
              </li>
            </ul>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :text, :string, required: true

  defp inline_code(assigns) do
    segments =
      assigns.text
      |> String.split(~r/`([^`]+)`/, include_captures: true, trim: true)
      |> Enum.map(fn seg ->
        if String.starts_with?(seg, "`") and String.ends_with?(seg, "`") and byte_size(seg) >= 2 do
          {:code, String.slice(seg, 1..-2//1)}
        else
          {:text, seg}
        end
      end)

    assigns = assign(assigns, :segments, segments)

    ~H"""
    <%= for {kind, value} <- @segments do %>
      <%= if kind == :code do %>
        <code>{value}</code>
      <% else %>
        {value}
      <% end %>
    <% end %>
    """
  end
end
