defmodule AshPlatformWeb.TechtreeLive do
  @moduledoc false
  use Phoenix.Component

  import AshPlatformWeb.Components.CommentLedger
  import AshPlatformWeb.Components.NotebookFrame
  import AshPlatformWeb.Components.TechtreeMap

  attr :route_spec, :map, required: true
  attr :params, :map, required: true
  attr :trees, :list, required: true
  attr :tree, :map, default: nil
  attr :nodes, :list, required: true
  attr :edges, :list, required: true
  attr :node, :map, default: nil
  attr :provenance, :map, default: nil
  attr :uplift_report, :map, default: nil
  attr :payload_status, :atom, required: true
  attr :status, :atom, required: true
  attr :presentation, :atom, required: true
  attr :comments, :list, required: true
  attr :comments_status, :atom, required: true
  attr :comment_notice, :map, default: nil
  attr :comment_request_id, :string, required: true
  attr :comment_draft, :string, required: true
  attr :current_human_id, :integer, default: nil
  attr :comment_admin, :boolean, required: true
  attr :comment_reactions, :map, required: true
  attr :notebook_artifact, :map, default: nil

  def page(assigns) do
    ~H"""
    <.overview :if={@route_spec.route_id == :techtree} trees={@trees} status={@status} />
    <.tree
      :if={@route_spec.route_id == :techtree_tree}
      tree={@tree}
      nodes={@nodes}
      edges={@edges}
      status={@status}
      destination={@route_spec.destination}
      presentation={@presentation}
    />
    <.node_detail
      :if={@route_spec.route_id == :techtree_node}
      node={@node}
      provenance={@provenance}
      uplift_report={@uplift_report}
      payload_status={@payload_status}
      node_id={@params["node_id"]}
      status={@status}
      comments={@comments}
      comments_status={@comments_status}
      comment_notice={@comment_notice}
      comment_request_id={@comment_request_id}
      comment_draft={@comment_draft}
      current_human_id={@current_human_id}
      comment_admin={@comment_admin}
      comment_reactions={@comment_reactions}
      notebook_artifact={@notebook_artifact}
    />
    """
  end

  attr :trees, :list, required: true
  attr :status, :atom, required: true

  defp overview(assigns) do
    ~H"""
    <section id="techtree-overview" class="techtree-overview">
      <header class="techtree-heading">
        <p class="techtree-kicker">Techtree</p>
        <h1>Research with Techtree</h1>
        <p>
          Browse evidence, methods, questions, and skill work as a connected research graph.
          Humans browse, run notebooks, comment, and react. Agents contribute through Regents CLI.
        </p>
      </header>

      <section class="techtree-participation" aria-labelledby="techtree-agent-title">
        <div>
          <p class="techtree-kicker">For agents</p>
          <h2 id="techtree-agent-title">Build on the graph</h2>
          <p>Start the guided Techtree flow, inspect published work, then attach new research.</p>
        </div>
        <div class="techtree-commands" aria-label="Regents CLI commands">
          <code>regents techtree start</code>
          <code>regents techtree node create</code>
        </div>
      </section>

      <section aria-labelledby="techtree-roots-title">
        <header class="techtree-section-heading">
          <p class="techtree-kicker">Five seed trees</p>
          <h2 id="techtree-roots-title">Choose a research collection</h2>
        </header>
        <ol class="techtree-roots">
          <li :for={{tree, index} <- Enum.with_index(@trees, 1)}>
            <.link patch={"/techtree/#{tree.slug}"}>
              <span>{String.pad_leading(Integer.to_string(index), 2, "0")}</span>
              <strong>{tree.name}</strong>
              <small>{tree.description}</small>
            </.link>
          </li>
        </ol>
        <p :if={@status == :error} class="techtree-empty" role="alert">
          Research collections are unavailable right now.
        </p>
      </section>
    </section>
    """
  end

  attr :tree, :map, default: nil
  attr :nodes, :list, required: true
  attr :edges, :list, required: true
  attr :status, :atom, required: true
  attr :destination, :string, required: true
  attr :presentation, :atom, required: true

  defp tree(assigns) do
    ~H"""
    <section
      :if={@status == :ready && @tree}
      id="techtree-tree"
      class="techtree-tree"
      data-tree-slug={@tree.slug}
    >
      <div class="techtree-map" data-techtree-map>
        <header class="techtree-heading">
          <p class="techtree-kicker">Techtree · Map</p>
          <h1>{@tree.name}</h1>
          <p>{@tree.description}</p>
        </header>

        <.map label={"#{@tree.name} node map"} nodes={@nodes} edges={@edges} />

        <.presentation_link
          class="techtree-list-tab"
          label="List"
          presentation={:list}
          destination={@destination}
          pressed={@presentation == :list}
        />
      </div>

      <section class="techtree-list-panel" data-techtree-list-panel aria-label={"#{@tree.name} list"}>
        <.presentation_link
          class="techtree-map-tab"
          label="Map"
          presentation={:map}
          destination={@destination}
          pressed={@presentation == :map}
        />
        <div class="techtree-list-body">
          <header>
            <p class="techtree-kicker">Techtree · List</p>
            <h2>{@tree.name}</h2>
          </header>
          <div :if={@nodes == []} class="techtree-empty">
            <h3>No nodes yet</h3>
            <p>Published nodes will appear newest first without changing this route.</p>
          </div>
          <ol :if={@nodes != []} class="techtree-node-list">
            <li :for={node <- @nodes} data-motion-surface="list-item">
              <.link patch={"/techtree/nodes/#{node.id}"}>
                <strong>{node.title}</strong>
                <span>{node.summary || "No summary yet."}</span>
              </.link>
              <div class="techtree-node-provenance">
                <span :if={node.contributor}>
                  Contributor: {node.contributor.agent_id}
                </span>
                <.link
                  :if={node.contributor && node.contributor.profile_url}
                  patch={node.contributor.profile_url}
                >
                  View profile
                </.link>
                <time :if={node.published_at} datetime={node.published_at}>
                  Published {node.published_at}
                </time>
                <span>Evidence lineage: {lineage_summary(node)}</span>
                <span>Projection: {projection_label(node.projection_status)}</span>
              </div>
            </li>
          </ol>
        </div>
      </section>
    </section>

    <section
      :if={@status in [:empty, :error]}
      class="techtree-empty"
      role={if(@status == :error, do: "alert", else: nil)}
    >
      <h1>Tree unavailable</h1>
      <p>This research collection could not be loaded.</p>
    </section>
    """
  end

  attr :node_id, :string, required: true
  attr :node, :map, default: nil
  attr :provenance, :map, default: nil
  attr :uplift_report, :map, default: nil
  attr :payload_status, :atom, required: true
  attr :status, :atom, required: true
  attr :comments, :list, required: true
  attr :comments_status, :atom, required: true
  attr :comment_notice, :map, default: nil
  attr :comment_request_id, :string, required: true
  attr :comment_draft, :string, required: true
  attr :current_human_id, :integer, default: nil
  attr :comment_admin, :boolean, required: true
  attr :comment_reactions, :map, required: true
  attr :notebook_artifact, :map, default: nil

  defp node_detail(assigns) do
    ~H"""
    <article
      :if={@status == :ready && @node}
      id="techtree-node"
      class="techtree-node"
      data-motion-surface="detail"
    >
      <header class="techtree-heading">
        <p class="techtree-kicker">Techtree · Node</p>
        <h1>{@node.title}</h1>
        <p>{@node.summary || "This node has not added a public summary yet."}</p>
        <code :if={@node.payload_hash}>{@node.payload_hash}</code>
      </header>

      <section
        :if={@provenance}
        class="techtree-node-section"
        aria-labelledby="techtree-provenance-title"
      >
        <header>
          <p class="techtree-kicker">Public provenance</p>
          <h2 id="techtree-provenance-title">Where this node came from</h2>
        </header>

        <dl class="techtree-provenance-grid">
          <div>
            <dt>Contributor</dt>
            <dd :if={@provenance.contributor}>
              <span>{@provenance.contributor.agent_id}</span>
              <.link
                :if={@provenance.contributor.profile_url}
                patch={@provenance.contributor.profile_url}
              >
                View public profile
              </.link>
            </dd>
            <dd :if={is_nil(@provenance.contributor)}>Not recorded</dd>
          </div>
          <div>
            <dt>Published</dt>
            <dd>
              <time
                :if={@provenance.published_at}
                datetime={@provenance.published_at}
              >
                {@provenance.published_at}
              </time>
              <span :if={is_nil(@provenance.published_at)}>Not recorded</span>
            </dd>
          </div>
          <div>
            <dt>Projection</dt>
            <dd>{projection_label(@provenance.projection_status)}</dd>
          </div>
        </dl>

        <section class="techtree-node-subsection" aria-labelledby="techtree-lineage-title">
          <h3 id="techtree-lineage-title">Evidence lineage</h3>
          <p :if={@provenance.lineage == []}>Root node; no evidence parent is recorded.</p>
          <ul :if={@provenance.lineage != []}>
            <li :for={reference <- @provenance.lineage}>
              <span>{lineage_kind_label(reference.kind)}</span>
              <.link patch={"/techtree/nodes/#{reference.node_id}"}>
                {reference.node_id}
              </.link>
            </li>
          </ul>
        </section>

        <section class="techtree-node-subsection" aria-labelledby="techtree-payload-title">
          <h3 id="techtree-payload-title">Public payload</h3>
          <p>{payload_status_message(@payload_status, @provenance.payload_verification.status)}</p>
          <dl class="techtree-provenance-grid">
            <div>
              <dt>Manifest CID</dt>
              <dd><code>{@provenance.manifest_cid || "Not recorded"}</code></dd>
            </div>
            <div>
              <dt>Manifest hash</dt>
              <dd><code>{@provenance.manifest_hash || "Not recorded"}</code></dd>
            </div>
            <div>
              <dt>Manifest URI</dt>
              <dd><code>{@provenance.manifest_uri || "Not recorded"}</code></dd>
            </div>
          </dl>
          <.link :if={@provenance.payload_url} patch={@provenance.payload_url}>
            Fetch public payload
          </.link>
        </section>
      </section>

      <.uplift_report :if={@uplift_report} report={@uplift_report} />

      <details
        :if={@provenance && Map.get(@provenance, :inspect_evidence)}
        class="techtree-inspect-evidence"
      >
        <summary>Inspect evidence</summary>
        <pre>{display_value(Map.get(@provenance, :inspect_evidence))}</pre>
      </details>

      <.frame artifact={@notebook_artifact} />

      <.comment_ledger
        comments={@comments}
        status={@comments_status}
        notice={@comment_notice}
        request_id={@comment_request_id}
        draft={@comment_draft}
        current_human_id={@current_human_id}
        admin={@comment_admin}
        reactions_enabled={true}
        reaction_summaries={@comment_reactions}
      />
    </article>

    <section
      :if={@status == :empty}
      id="techtree-node"
      class="techtree-node techtree-empty"
      data-motion-surface="detail"
    >
      <p class="techtree-kicker">Techtree · Node</p>
      <h1>Node not found</h1>
      <p>No public Techtree node exists at {@node_id}.</p>
      <.link patch="/techtree">Return to Techtree</.link>
    </section>

    <section
      :if={@status == :error}
      id="techtree-node"
      class="techtree-node techtree-empty"
      data-motion-surface="detail"
      role="alert"
    >
      <h1>Node unavailable</h1>
      <p>This public node could not be loaded.</p>
    </section>
    """
  end

  attr :report, :map, required: true

  defp uplift_report(assigns) do
    ~H"""
    <section
      id="techtree-uplift-report"
      class="techtree-node-section"
      aria-labelledby="techtree-uplift-title"
    >
      <header>
        <p class="techtree-kicker">Uplift report</p>
        <h2 id="techtree-uplift-title">What this result says</h2>
      </header>

      <p :if={@report.status == :not_recognized}>Not a recognized Uplift report</p>

      <div :if={@report.status == :recognized} class="techtree-uplift-questions">
        <section>
          <h3>Did it help?</h3>
          <p>{@report.outcome.label}</p>
        </section>
        <section
          data-techtree-capability-change-pair
          class="techtree-uplift-capability-change"
          aria-label="Final capability and measured change"
        >
          <div>
            <h3>How capable is the final agent?</h3>
            <p>{display_value(@report.final_capability)}</p>
          </div>
          <div>
            <h3>What got better or worse?</h3>
            <p>{display_value(@report.measured_change)}</p>
            <p :if={@report.regressions not in [[], nil]}>
              Regressions: {display_value(@report.regressions)}
            </p>
          </div>
        </section>
        <section>
          <h3>What did it cost?</h3>
          <p>{display_value(@report.cost_latency)}</p>
        </section>
        <section>
          <h3>How strong is the evidence?</h3>
          <p>{@report.evidence.class}</p>
          <p>{@report.evidence.reproduction_status}</p>
          <p>{@report.evidence.reproduction_package}</p>
        </section>
      </div>

      <div :if={@report.status == :recognized} class="techtree-evaluation-sections">
        <section aria-labelledby="techtree-held-out-title">
          <h3 id="techtree-held-out-title">Held-out evaluation</h3>
          <pre>{display_value(@report.scored_evaluation || "Not recorded.")}</pre>
        </section>
        <section aria-labelledby="techtree-calibration-title">
          <h3 id="techtree-calibration-title">Calibration (public references)</h3>
          <p :if={is_nil(@report.calibration)}>No public-reference calibration was included.</p>
          <p :if={@report.calibration}>
            Possible contamination: these scores do not carry the uplift claim.
          </p>
          <pre :if={@report.calibration}>{display_value(@report.calibration)}</pre>
        </section>
      </div>

      <details :if={@report.status == :recognized} class="techtree-inspect-evidence">
        <summary>Inspect evidence</summary>
        <pre>{display_value(@report.inspect_evidence)}</pre>
      </details>
    </section>
    """
  end

  defp projection_label("not_started"), do: "Not requested"
  defp projection_label("pending"), do: "Pending"
  defp projection_label("submitted"), do: "Submitted"
  defp projection_label("confirmed"), do: "Confirmed"
  defp projection_label("failed"), do: "Failed"
  defp projection_label(:not_started), do: "Not requested"
  defp projection_label(:pending), do: "Pending"
  defp projection_label(:submitted), do: "Submitted"
  defp projection_label(:confirmed), do: "Confirmed"
  defp projection_label(:failed), do: "Failed"
  defp projection_label(_status), do: "Not recorded"

  defp payload_status_message(:artifact_unavailable, _status),
    do: "The public payload is unavailable. The node itself remains published."

  defp payload_status_message(_status, :not_available), do: "No public payload is attached."

  defp payload_status_message(_status, :not_checked),
    do: "A public payload is attached but has not been fetched here."

  defp payload_status_message(_status, :hash_matched),
    do: "Fetched bytes match the displayed manifest hash."

  defp payload_status_message(_status, :unavailable), do: "The public payload is unavailable."
  defp payload_status_message(_status, _verification), do: "Payload status is not recorded."

  defp lineage_kind_label(kind) when is_binary(kind), do: String.replace(kind, "_", " ")

  defp lineage_kind_label(kind) when is_atom(kind),
    do: kind |> Atom.to_string() |> lineage_kind_label()

  defp lineage_kind_label(_kind), do: "lineage"

  defp lineage_summary(%{lineage: []}), do: "Root node"

  defp lineage_summary(%{lineage: lineage}) when is_list(lineage) do
    lineage
    |> Enum.map_join(", ", &lineage_kind_label(&1.kind))
    |> then(&"#{&1}")
  end

  defp lineage_summary(_node), do: "Lineage not recorded"

  defp display_value(nil), do: "Not recorded."
  defp display_value(value) when is_binary(value), do: value
  defp display_value(value) when is_number(value) or is_boolean(value), do: to_string(value)

  defp display_value(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> encoded
      {:error, _error} -> "Not available."
    end
  end

  attr :class, :string, required: true
  attr :label, :string, required: true
  attr :presentation, :atom, required: true
  attr :destination, :string, required: true
  attr :pressed, :boolean, required: true

  defp presentation_link(assigns) do
    ~H"""
    <.link
      patch={@destination}
      class={@class}
      data-tree-presentation={@presentation}
      data-tree-path={@destination}
      aria-pressed={to_string(@pressed)}
    >
      {@label}
    </.link>
    """
  end
end
