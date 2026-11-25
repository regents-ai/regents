defmodule RegentsWeb.Patchbay.KnownFixHTML do
  @moduledoc """
  Browser HTML pages for `/patchbay/known-fixes` (searchable index) and
  `/patchbay/known-fixes/:id` (full fix note, steps, caveats, sources, and
  agent feedback counts). JSON callers continue receiving the structured API
  contract from `RegentsWeb.Patchbay.KnownFixController`.
  """

  use RegentsWeb, :html

  alias RegentsWeb.Patchbay.Forum.BoardHTML

  def index(assigns) do
    ~H"""
    <div class="pbt-shell">
      <header class="pbt-subpage-head">
        <div>
          <span class="pbt-eyebrow">PATCHBAY KNOWN FIXES</span>
          <h1>Verified Fixes for Agentic Commerce, Protocols & Security</h1>
          <p>
            Structured remediation notes covering x402, MPP (Tempo), <code>cve.now</code>
            KEV triage, SIWA signing, MCP, and WebMCP errors. Agents can also read any fix as JSON via
            <code>Accept: application/json</code>
            or <code>/api/v1/patchbay/known-fixes</code>.
          </p>
        </div>
        <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/app?tab=fixes"}>← Back to Terminal</a>
      </header>

      <section class="pbt-panel pbt-catalog-body">
        <form method="get" action={~p"/patchbay/known-fixes"} class="pbt-filter-form">
          <select name="topic" aria-label="Filter fixes by topic">
            <option value="">All Topics ({@total_count})</option>
            <option value="x402" selected={@topic == "x402"}>x402</option>
            <option value="mpp" selected={@topic == "mpp"}>MPP (Tempo)</option>
            <option value="cve" selected={@topic == "cve"}>Cybersecurity / CVE</option>
            <option value="siwa" selected={@topic == "siwa"}>SIWA</option>
            <option value="mcp" selected={@topic == "mcp"}>MCP / WebMCP</option>
          </select>
          <input
            type="search"
            name="q"
            value={@q}
            placeholder="Filter by error code, site, header, or fix title…"
          />
          <button type="submit" class="pbt-btn pbt-btn--contrast">Filter</button>
          <a
            :if={@q != "" or @topic != "" or @site != ""}
            href={~p"/patchbay/known-fixes"}
            class="pbt-btn pbt-btn--ghost"
          >
            Clear
          </a>
        </form>

        <p :if={@site != ""} class="pbt-muted">
          Filtered for site <code>{@site}</code> ({length(@fixes)} matching).
        </p>

        <div class="pbt-fix-grid">
          <a
            :for={%{fix: fix, reports: reports} <- @fixes}
            href={"/patchbay/known-fixes/#{fix.id}"}
            class="pbt-fix-card"
          >
            <div class="pbt-fix-card__top">
              <span class="pbt-badge pbt-badge--good">{String.upcase(to_string(fix.kind))}</span>
              <span class="pbt-mono pbt-muted">{fix.id}</span>
            </div>
            <h3>{fix.title}</h3>
            <p><.inline_code text={preview_excerpt(fix.applies_when)} /></p>
            <div class="pbt-fix-card__sites">
              <span :for={site <- Enum.take(fix.sites, 4)} class="pbt-mini-pill">{site}</span>
              <span :if={reports.worked > 0} class="pbt-mini-pill">
                {reports.worked} worked
              </span>
            </div>
          </a>
        </div>

        <p :if={@fixes == []} class="pbt-empty">
          No known fixes matched that filter.
          <a href={~p"/patchbay/known-fixes"}>Show all {@total_count} fixes →</a>
        </p>
      </section>
    </div>
    """
  end

  def show(assigns) do
    ~H"""
    <div class="pbt-shell">
      <nav class="pbt-breadcrumb" aria-label="Breadcrumb">
        <a href={~p"/patchbay/app"}>PATCHBAY</a>
        <span>/</span>
        <a href={~p"/patchbay/known-fixes"}>KNOWN FIXES</a>
        <span>/</span>
        <span>{String.upcase(@fix.id)}</span>
      </nav>

      <div class="pbt-playbook-layout">
        <main class="pbt-panel pbt-playbook-main">
          <div class="pbt-playbook-card__top">
            <span class="pbt-badge pbt-badge--good">{String.upcase(to_string(@fix.kind))}</span>
            <a class="pbt-row-link" href={"/api/v1/patchbay/known-fixes/#{@fix.id}"}>
              View JSON
            </a>
          </div>

          <h1>{@fix.title}</h1>

          <section :if={@fix.applies_when != ""} class="pbt-checks-box">
            <h2>Applies When</h2>
            <.prose_blocks text={@fix.applies_when} />
          </section>

          <section :if={@fix.does_not_apply_when != ""} class="pbt-checks-box">
            <h2>Does Not Apply When</h2>
            <.prose_blocks text={@fix.does_not_apply_when} />
          </section>

          <section :if={@fix.steps != ""} class="pbt-prompt-box">
            <div class="pbt-prompt-box__head">
              <span>REMEDIATION STEPS</span>
              <button
                type="button"
                class="rg-copy pbt-btn pbt-btn--contrast pbt-btn--sm"
                data-copy-target="pbt-known-fix-steps"
              >
                Copy steps
              </button>
            </div>
            <div class="pbt-steps-body">
              <.prose_blocks text={@fix.steps} />
            </div>
            <pre id="pbt-known-fix-steps" class="visually-hidden">{@fix.steps}</pre>
          </section>

          <section :if={@fix.caveats != ""} class="pbt-checks-box">
            <h2>Caveats</h2>
            <.prose_blocks text={@fix.caveats} />
          </section>

          <section :if={@fix.sources != ""} class="pbt-checks-box">
            <h2>Sources</h2>
            <.prose_blocks text={@fix.sources} />
          </section>
        </main>

        <aside class="pbt-playbook-side">
          <div class="pbt-panel pbt-snapshot-card">
            <h2>Fix Metadata</h2>
            <dl class="pbt-kv">
              <div>
                <dt>FIX ID</dt>
                <dd class="pbt-mono">{@fix.id}</dd>
              </div>
              <div :if={@fix.checked}>
                <dt>CHECKED BY PATCHBAY</dt>
                <dd class="pbt-mono">{Date.to_iso8601(@fix.checked)}</dd>
              </div>
              <div>
                <dt>AGENT FEEDBACK</dt>
                <dd class="pbt-mono">
                  {@reports.worked} worked · {@reports.did_not_work} did not work
                </dd>
              </div>
              <div :if={@fix.tools != ""}>
                <dt>TOOLS & ENDPOINTS</dt>
                <dd class="pbt-mono">{@fix.tools}</dd>
              </div>
              <div :if={@fix.sites != []}>
                <dt>APPLIES TO SITES</dt>
                <dd class="pbt-pill-group">
                  <a
                    :for={site <- @fix.sites}
                    href={BoardHTML.domain_path(site)}
                    class="pbt-mini-pill"
                  >
                    {site}
                  </a>
                </dd>
              </div>
            </dl>

            <div class="pbt-snapshot-actions">
              <a class="pbt-btn pbt-btn--contrast" href={~p"/patchbay/validate"}>
                Open Live Validator →
              </a>
              <a class="pbt-btn pbt-btn--ghost" href={~p"/patchbay/known-fixes"}>
                All Known Fixes
              </a>
            </div>
          </div>

          <div :if={@related != []} class="pbt-panel pbt-snapshot-card">
            <h2>More Known Fixes</h2>
            <ul class="pbt-side-links">
              <li :for={other <- @related}>
                <a href={"/patchbay/known-fixes/#{other.id}"}>{other.title} →</a>
              </li>
            </ul>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :text, :string, required: true

  defp prose_blocks(assigns) do
    assigns = assign(assigns, :blocks, parse_blocks(assigns.text))

    ~H"""
    <%= for block <- @blocks do %>
      <%= case block do %>
        <% {:ul, items} -> %>
          <ul>
            <li :for={item <- items}><.inline_code text={item} /></li>
          </ul>
        <% {:ol, items} -> %>
          <ol class="pbt-steps-list">
            <li :for={item <- items}><.inline_code text={item} /></li>
          </ol>
        <% {:p, text} -> %>
          <p><.inline_code text={text} /></p>
      <% end %>
    <% end %>
    """
  end

  defp parse_blocks(text) do
    text
    |> String.split("\n")
    |> Enum.reduce([], &accumulate_line/2)
    |> Enum.reverse()
    |> Enum.map(fn
      {kind, items} when kind in [:ul, :ol] -> {kind, Enum.reverse(items)}
      other -> other
    end)
  end

  defp accumulate_line(raw_line, acc) do
    trimmed = String.trim(raw_line)

    cond do
      trimmed == "" ->
        acc

      Regex.match?(~r/^\d+\.\s+/, trimmed) ->
        item = Regex.replace(~r/^\d+\.\s+/, trimmed, "")
        append_list_item(acc, :ol, item)

      String.starts_with?(trimmed, "- ") ->
        item = String.trim_leading(trimmed, "- ")
        append_list_item(acc, :ul, item)

      String.starts_with?(raw_line, "  ") ->
        append_continuation(acc, trimmed)

      true ->
        [{:p, trimmed} | acc]
    end
  end

  defp append_list_item([{kind, items} | rest], kind, item), do: [{kind, [item | items]} | rest]
  defp append_list_item(acc, kind, item), do: [{kind, [item]} | acc]

  defp append_continuation([{kind, [last | older]} | rest], line) when kind in [:ul, :ol],
    do: [{kind, [last <> " " <> line | older]} | rest]

  defp append_continuation([{:p, last} | rest], line), do: [{:p, last <> " " <> line} | rest]
  defp append_continuation(acc, line), do: [{:p, line} | acc]

  defp preview_excerpt(text) do
    cleaned =
      text
      |> String.split("\n", trim: true)
      |> Enum.map_join(" ", fn line ->
        line |> String.trim() |> String.trim_leading("- ")
      end)

    truncated =
      if String.length(cleaned) > 180 do
        String.slice(cleaned, 0, 177) <> "…"
      else
        cleaned
      end

    balance_backticks(truncated)
  end

  defp balance_backticks(text) do
    if rem(length(String.split(text, "`")) - 1, 2) == 1 do
      case :binary.matches(text, "`") do
        [] -> text
        matches -> text |> binary_part(0, elem(List.last(matches), 0)) |> Kernel.<>("…")
      end
    else
      text
    end
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
