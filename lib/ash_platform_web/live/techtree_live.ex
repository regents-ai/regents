defmodule AshPlatformWeb.TechtreeLive do
  @moduledoc false
  use Phoenix.Component

  import AshPlatformWeb.Components.CommentLedger
  import AshPlatformWeb.Components.NotebookFrame

  attr :route_spec, :map, required: true
  attr :params, :map, required: true
  attr :trees, :list, required: true
  attr :tree, :map, default: nil
  attr :nodes, :list, required: true
  attr :node, :map, default: nil
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
      status={@status}
      destination={@route_spec.destination}
      presentation={@presentation}
    />
    <.node_detail
      :if={@route_spec.route_id == :techtree_node}
      node={@node}
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
        <div class="techtree-commands" aria-label="Verified Regents CLI commands">
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

        <div class="techtree-map-stage" aria-label={"#{@tree.name} node map"}>
          <div :if={@nodes == []} class="techtree-empty">
            <h2>No nodes yet</h2>
            <p>Published nodes will appear here as the tree's connected map.</p>
          </div>
          <ol :if={@nodes != []} class="techtree-map-nodes">
            <li :for={{node, index} <- Enum.with_index(@nodes, 1)}>
              <.link patch={"/techtree/nodes/#{node.id}"}>
                <span>{String.pad_leading(Integer.to_string(index), 2, "0")}</span>
                <strong>{node.title}</strong>
              </.link>
            </li>
          </ol>
        </div>

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
