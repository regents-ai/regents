defmodule AshPlatformWeb.Components.TechtreeMap do
  @moduledoc false
  use Phoenix.Component

  @fallback_columns 3
  @node_width 240
  @node_height 112
  @world_margin 72
  @fallback_column_gap 64
  @fallback_row_gap 64

  attr :label, :string, required: true
  attr :nodes, :list, required: true
  attr :edges, :list, required: true

  def map(assigns) do
    assigns = assign(assigns, :layout, layout(assigns.nodes, assigns.edges))

    ~H"""
    <div
      id="techtree-map-stage"
      class="techtree-map-stage"
      phx-hook="TechtreeCamera"
      aria-label={@label}
      tabindex="0"
    >
      <div :if={@nodes == []} class="techtree-empty">
        <h2>No nodes yet</h2>
        <p>Published nodes will appear here as the tree's connected map.</p>
      </div>

      <div
        :if={@nodes != []}
        class="techtree-map-world"
        data-techtree-map-world
        data-world-width={@layout.width}
        data-world-height={@layout.height}
        style={
          "--world-width: #{@layout.width}px; --world-height: #{@layout.height}px; " <>
            "--techtree-node-width: #{@layout.node_width}px; " <>
            "--techtree-node-height: #{@layout.node_height}px;"
        }
      >
        <svg
          class="techtree-map-edges"
          data-techtree-map-edges
          viewBox={"0 0 #{@layout.width} #{@layout.height}"}
          aria-hidden="true"
          focusable="false"
        >
          <path
            :for={edge <- @layout.edges}
            class={["techtree-map-edge", "techtree-map-edge--#{edge.kind}"]}
            data-edge-kind={edge.kind}
            data-from-node-id={edge.from_node_id}
            data-to-node-id={edge.to_node_id}
            d={edge.path}
          />
        </svg>

        <ol class="techtree-map-nodes">
          <li
            :for={placed <- @layout.nodes}
            class="techtree-map-node"
            data-node-id={placed.node.id}
            data-position-source={placed.source}
            data-display-kind={placed.display_kind}
            data-node-x={placed.x}
            data-node-y={placed.y}
            style={"--node-x: #{placed.x}px; --node-y: #{placed.y}px;"}
          >
            <.link patch={"/techtree/nodes/#{placed.node.id}"}>
              <span class="techtree-map-node-index">{placed.index}</span>
              <strong>{placed.node.title}</strong>
              <span :if={placed.display_kind == "featured"} class="techtree-map-node-kind">
                Featured
              </span>
              <small>Projection: {projection_label(placed.node.projection_status)}</small>
            </.link>
            <div class="techtree-map-node-provenance">
              <.link
                :if={placed.node.contributor && placed.node.contributor.profile_url}
                patch={placed.node.contributor.profile_url}
              >
                {placed.node.contributor.agent_id}
              </.link>
              <span :if={placed.node.contributor && is_nil(placed.node.contributor.profile_url)}>
                {placed.node.contributor.agent_id}
              </span>
              <time :if={placed.node.published_at} datetime={placed.node.published_at}>
                {placed.node.published_at}
              </time>
              <span>{lineage_summary(placed.node)}</span>
            </div>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  defp layout(nodes, edges) do
    fallback_y = fallback_start_y(nodes)

    {placed_nodes, _fallback_count} =
      nodes
      |> Enum.with_index(1)
      |> Enum.map_reduce(0, fn {node, index}, fallback_index ->
        {x, y, source, fallback_index} =
          node_position(node, fallback_y, fallback_index)

        placed = %{
          node: node,
          index: String.pad_leading(Integer.to_string(index), 2, "0"),
          display_kind: node.display_kind,
          source: source,
          x: x,
          y: y
        }

        {placed, fallback_index}
      end)

    positions = Map.new(placed_nodes, &{&1.node.id, &1})

    %{
      nodes: placed_nodes,
      edges: edge_layout(edges, positions),
      width: world_width(placed_nodes),
      height: world_height(placed_nodes),
      node_width: @node_width,
      node_height: @node_height
    }
  end

  defp node_position(%{pos_x: x, pos_y: y}, _fallback_y, fallback_index)
       when is_number(x) and is_number(y) do
    {x, y, "authored", fallback_index}
  end

  defp node_position(_node, fallback_y, fallback_index) do
    column = rem(fallback_index, @fallback_columns)
    row = div(fallback_index, @fallback_columns)

    x = @world_margin + column * (@node_width + @fallback_column_gap)
    y = fallback_y + row * (@node_height + @fallback_row_gap)

    {x, y, "fallback", fallback_index + 1}
  end

  defp fallback_start_y(nodes) do
    authored_y =
      nodes
      |> Enum.filter(&(is_number(&1.pos_x) and is_number(&1.pos_y)))
      |> Enum.map(& &1.pos_y)

    case authored_y do
      [] -> @world_margin
      values -> Enum.max(values) + @node_height + @world_margin
    end
  end

  defp edge_layout(edges, positions) do
    Enum.map(edges, fn edge ->
      from = Map.fetch!(positions, edge.from_node_id)
      to = Map.fetch!(positions, edge.to_node_id)
      from_x = from.x + @node_width / 2
      from_y = from.y + @node_height / 2
      to_x = to.x + @node_width / 2
      to_y = to.y + @node_height / 2

      %{
        from_node_id: edge.from_node_id,
        to_node_id: edge.to_node_id,
        kind: edge_kind(edge.kind),
        path: "M #{from_x} #{from_y} L #{to_x} #{to_y}"
      }
    end)
  end

  defp edge_kind(:related), do: "related"
  defp edge_kind(:prerequisite), do: "prerequisite"

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

  defp lineage_summary(%{lineage: []}), do: "Root node"

  defp lineage_summary(%{lineage: lineage}) when is_list(lineage) do
    lineage
    |> Enum.map_join(", ", &lineage_kind_label(&1.kind))
  end

  defp lineage_summary(_node), do: "Lineage not recorded"

  defp lineage_kind_label(kind) when is_binary(kind), do: String.replace(kind, "_", " ")

  defp lineage_kind_label(kind) when is_atom(kind),
    do: kind |> Atom.to_string() |> lineage_kind_label()

  defp lineage_kind_label(_kind), do: "lineage"

  defp world_width(nodes) do
    nodes
    |> Enum.map(&(&1.x + @node_width + @world_margin))
    |> Enum.max(fn -> 0 end)
    |> ceil()
  end

  defp world_height(nodes) do
    nodes
    |> Enum.map(&(&1.y + @node_height + @world_margin))
    |> Enum.max(fn -> 0 end)
    |> ceil()
  end
end
