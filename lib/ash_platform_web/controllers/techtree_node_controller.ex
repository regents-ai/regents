defmodule AshPlatformWeb.TechtreeNodeController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Techtree

  def index(%Plug.Conn{query_string: ""} = conn, _params) do
    techtree = conn.private[:techtree_node_controller_techtree] || Techtree

    case techtree.list_public_nodes(actor: nil) do
      {:ok, nodes} -> json(conn, %{data: Enum.map(nodes, &public_node/1)})
      {:error, _error} -> internal_error(conn)
    end
  end

  def index(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{
        code: "invalid_request",
        message: "Query parameters are not supported."
      }
    })
  end

  defp public_node(node) do
    %{
      id: node.id,
      tree_id: node.tree_id,
      title: node.title,
      summary: node.summary,
      payload_hash: node.payload_hash,
      published_at: DateTime.to_iso8601(node.published_at)
    }
  end

  defp internal_error(conn) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{
      error: %{
        code: "internal_error",
        message: "The request could not be completed."
      }
    })
  end
end
