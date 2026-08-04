defmodule AshPlatform.Techtree.Pagination do
  @moduledoc false

  import Ash.Expr

  require Ash.Query

  alias AshPlatform.Techtree.Node

  def page(tree_id, decoded_cursor, limit, opts \\ [])

  def page(tree_id, decoded_cursor, limit, opts) when is_integer(limit) and limit in 1..100 do
    with {:ok, after_key} <- bind(decoded_cursor, tree_id),
         {:ok, nodes} <- read_page(tree_id, after_key, limit, opts) do
      {page_nodes, remainder} = Enum.split(nodes, limit)

      next_cursor =
        if remainder != [] do
          page_nodes
          |> List.last()
          |> encode()
        end

      {:ok, %{nodes: page_nodes, next_cursor: next_cursor}}
    end
  end

  def page(_tree_id, _decoded_cursor, _limit, _opts), do: {:error, :invalid_input}

  def encode(%{tree_id: tree_id, published_at: published_at, id: id}) do
    [tree_id, DateTime.to_iso8601(published_at), id]
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def decode(nil, _opts), do: {:ok, nil}

  def decode(cursor, opts) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, [tree_id, published_at, id]}
         when is_binary(tree_id) and is_binary(published_at) and is_binary(id) <-
           Jason.decode(json),
         {:ok, tree_id} <- Ecto.UUID.cast(tree_id),
         {:ok, published_at, 0} <- DateTime.from_iso8601(published_at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      verify_cursor(tree_id, published_at, id, opts)
    else
      _error -> {:error, :invalid_input}
    end
  end

  def decode(_cursor, _opts), do: {:error, :invalid_input}

  defp bind(nil, _tree_id), do: {:ok, nil}

  defp bind(%{tree_id: cursor_tree_id, published_at: published_at, id: id}, tree_id)
       when cursor_tree_id == tree_id,
       do: {:ok, {published_at, id}}

  defp bind(_decoded_cursor, _tree_id), do: {:error, :invalid_input}

  defp verify_cursor(tree_id, published_at, id, opts) do
    case read_cursor_node(id, opts) do
      {:ok, node} when not is_nil(node) ->
        if node.tree_id == tree_id and DateTime.compare(node.published_at, published_at) == :eq do
          {:ok, %{tree_id: tree_id, published_at: published_at, id: id}}
        else
          {:error, :invalid_input}
        end

      {:ok, nil} ->
        {:error, :invalid_input}

      {:error, error} ->
        {:error, error}
    end
  end

  defp read_cursor_node(id, opts) do
    Node
    |> Ash.Query.for_read(:public_by_id, %{id: id}, opts)
    |> Ash.read_one(opts)
  end

  defp read_page(tree_id, after_key, limit, opts) do
    Node
    |> Ash.Query.for_read(:list_public_for_tree, %{tree_id: tree_id}, opts)
    |> after_cursor(after_key)
    |> Ash.Query.limit(limit + 1)
    |> Ash.read(opts)
  end

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, {published_at, id}) do
    Ash.Query.filter(
      query,
      expr(published_at < ^published_at or (published_at == ^published_at and id > ^id))
    )
  end
end
