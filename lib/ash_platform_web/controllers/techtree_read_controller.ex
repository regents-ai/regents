defmodule AshPlatformWeb.TechtreeReadController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Techtree
  alias AshPlatform.Techtree.Pagination

  @default_limit 25
  @maximum_limit 100
  @slug_pattern ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  @not_started_projection %{
    chain_id: 8453,
    projection_status: :not_started,
    record_uid: nil,
    transaction_hash: nil,
    block_number: nil
  }

  def trees(conn, params) do
    techtree = techtree(conn)

    with :ok <- allow_parameters(params, []),
         {:ok, trees} <- techtree.list_trees(actor: nil) do
      json(conn, %{data: Enum.map(trees, &public_tree/1)})
    else
      error -> render_error(conn, error)
    end
  end

  def tree_nodes(conn, %{"slug" => slug} = params) do
    techtree = techtree(conn)

    with :ok <- allow_parameters(params, ["slug", "cursor", "limit"]),
         :ok <- validate_slug(slug),
         :ok <- validate_cursor(params["cursor"]),
         {:ok, cursor} <- Pagination.decode(params["cursor"], actor: nil),
         {:ok, limit} <- parse_limit(params["limit"]),
         {:ok, tree} when not is_nil(tree) <- techtree.get_tree_by_slug(slug, actor: nil),
         {:ok, page} <- Pagination.page(tree.id, cursor, limit, actor: nil),
         {:ok, edges} <- techtree.list_tree_edges(tree.id, actor: nil) do
      json(conn, %{
        data: Enum.map(page.nodes, &public_node_list_item/1),
        edges: Enum.map(edges, &public_edge/1),
        next_cursor: page.next_cursor
      })
    else
      {:ok, nil} -> render_error(conn, :not_found)
      error -> render_error(conn, error)
    end
  end

  def node(conn, %{"id" => id} = params) do
    techtree = techtree(conn)

    with :ok <- allow_parameters(params, ["id"]),
         {:ok, id} <- validate_id(id),
         {:ok, node} when not is_nil(node) <- techtree.get_public_node(id, actor: nil),
         {:ok, edges} <- techtree.list_tree_edges(node.tree_id, actor: nil) do
      node_edges =
        Enum.filter(edges, &(&1.from_node_id == node.id or &1.to_node_id == node.id))

      json(conn, %{data: public_node(node, node_edges)})
    else
      {:ok, nil} -> render_error(conn, :not_found)
      error -> render_error(conn, error)
    end
  end

  defp techtree(conn),
    do: conn.private[:techtree_read_controller_techtree] || Techtree

  defp allow_parameters(params, allowed) do
    if Enum.all?(Map.keys(params), &(&1 in allowed)),
      do: :ok,
      else: {:error, :invalid_input}
  end

  defp validate_slug(slug) when is_binary(slug) do
    if byte_size(slug) <= 63 and Regex.match?(@slug_pattern, slug),
      do: :ok,
      else: {:error, :invalid_input}
  end

  defp validate_slug(_slug), do: {:error, :invalid_input}

  defp validate_cursor(nil), do: :ok

  defp validate_cursor(cursor) when is_binary(cursor) and byte_size(cursor) in 1..512, do: :ok

  defp validate_cursor(_cursor), do: {:error, :invalid_input}

  defp validate_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_input}
    end
  end

  defp parse_limit(nil), do: {:ok, @default_limit}

  defp parse_limit(limit) when is_binary(limit) do
    with {parsed, ""} <- Integer.parse(limit),
         true <- parsed >= 1 and parsed <= @maximum_limit do
      {:ok, parsed}
    else
      _error -> {:error, :invalid_input}
    end
  end

  defp parse_limit(_limit), do: {:error, :invalid_input}

  defp public_tree(tree) do
    %{
      id: tree.id,
      slug: tree.slug,
      name: tree.name,
      description: tree.description
    }
  end

  defp public_node_list_item(node) do
    %{
      id: node.id,
      tree_id: node.tree_id,
      title: node.title,
      summary: node.summary,
      payload_hash: node.payload_hash,
      display_kind: node.display_kind,
      published_at: DateTime.to_iso8601(node.published_at)
    }
    |> put_position(node)
  end

  defp public_node(node, edges) do
    %{
      id: node.id,
      tree_id: node.tree_id,
      kind: node.kind || node.display_kind,
      title: node.title,
      summary: node.summary,
      payload_hash: node.payload_hash,
      base_mainnet_projection: @not_started_projection,
      edges: Enum.map(edges, &public_edge/1),
      published_at: DateTime.to_iso8601(node.published_at)
    }
    |> put_position(node)
    |> put_recorded(node, :contributor_id)
    |> put_recorded(node, :lineage_node_ids)
    |> put_recorded(node, :capsule)
    |> put_recorded(node, :immutable_payloads)
    |> put_recorded(node, :evidence_projection)
    |> put_recorded(node, :evidence_state)
    |> put_recorded(node, :base_mainnet_projection)
  end

  defp put_position(payload, %{pos_x: x, pos_y: y}) when not is_nil(x) and not is_nil(y),
    do: Map.put(payload, :position, %{x: x, y: y})

  defp put_position(payload, _node), do: payload

  defp put_recorded(payload, node, field) do
    case Map.fetch(node, field) do
      {:ok, value} when not is_nil(value) -> Map.put(payload, field, value)
      _missing_or_nil -> payload
    end
  end

  defp public_edge(edge) do
    %{
      from_node_id: edge.from_node_id,
      to_node_id: edge.to_node_id,
      kind: edge.kind
    }
  end

  defp render_error(conn, {:error, reason}), do: render_error(conn, reason)

  defp render_error(conn, %Ash.Error.Forbidden{}),
    do: error(conn, :unauthorized, :unauthorized, "The request is not authorized.")

  defp render_error(conn, :unauthorized),
    do: error(conn, :unauthorized, :unauthorized, "The request is not authorized.")

  defp render_error(conn, :not_found),
    do: error(conn, :not_found, :not_found, "The requested public record was not found.")

  defp render_error(conn, :invalid_input),
    do: error(conn, :bad_request, :invalid_input, "The request input is invalid.")

  defp render_error(conn, _reason),
    do:
      error(
        conn,
        :service_unavailable,
        :temporarily_unavailable,
        "The public read is temporarily unavailable."
      )

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end
