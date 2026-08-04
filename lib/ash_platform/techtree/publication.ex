defmodule AshPlatform.Techtree.Publication do
  @moduledoc false

  alias AshPlatform.AgentAuth.AgentIdentity
  alias AshPlatform.Techtree.Node

  def publish(attributes, %AgentIdentity{} = actor, envelope) do
    with :ok <- admit_tree(attributes.tree_id) do
      transact(attributes, actor, envelope)
    end
  end

  defp transact(attributes, actor, envelope) do
    result =
      Ash.DataLayer.transaction(Node, fn ->
        with {:ok, draft} <- create_draft(attributes, actor, envelope),
             {:ok, publishing} <- update(draft, :mark_publication_publishing, %{}, actor),
             {:ok, published} <-
               update(
                 publishing,
                 :mark_publication_published,
                 %{published_at: DateTime.utc_now()},
                 actor
               ) do
          published
        else
          {:error, error} -> Ash.DataLayer.rollback(Node, error)
        end
      end)

    case result do
      {:ok, node} -> {:ok, node, false}
      {:error, error} -> resolve_create_error(attributes, actor, error)
    end
  end

  defp admit_tree(tree_id) do
    case Ecto.Adapters.SQL.query(
           AshPlatform.Repo,
           "SELECT 1 FROM techtree.trees WHERE id = $1",
           [Ecto.UUID.dump!(tree_id)]
         ) do
      {:ok, %{rows: [[1]]}} -> :ok
      {:ok, %{rows: []}} -> {:error, :invalid_input}
      {:error, _error} -> {:error, :temporarily_unavailable}
    end
  end

  defp create_draft(attributes, actor, envelope) do
    attributes =
      attributes
      |> Map.delete(:regent_id)
      |> Map.put(:siwa_envelope, stored_envelope(envelope))

    Node
    |> Ash.Changeset.for_create(:create_publication, attributes, actor: actor)
    |> Ash.create()
  end

  defp update(node, action, attributes, actor) do
    node
    |> Ash.Changeset.for_update(action, attributes, actor: actor)
    |> Ash.update()
  end

  defp resolve_create_error(attributes, actor, error) do
    case publication_by_key(actor, attributes.idempotency_key) do
      {:ok, nil} -> classify(error)
      {:ok, node} -> replay_or_conflict(node, attributes, actor)
      {:error, _lookup_error} -> {:error, :temporarily_unavailable}
    end
  end

  defp publication_by_key(actor, idempotency_key) do
    Node
    |> Ash.Query.for_read(
      :publication_by_key,
      %{
        registry_address: actor.registry_address,
        token_id: actor.token_id,
        idempotency_key: idempotency_key
      },
      actor: actor
    )
    |> Ash.read_one()
  end

  defp replay_or_conflict(node, attributes, actor) do
    if same_publication?(node, attributes, actor),
      do: {:ok, node, true},
      else: {:error, :conflict}
  end

  defp same_publication?(node, attributes, actor) do
    node.publisher_regent_id == actor.regent_id and
      node.tree_id == attributes.tree_id and
      node.kind == attributes.kind and
      node.title == attributes.title and
      node.summary == attributes.summary and
      node.payload_hash == attributes.payload_hash and
      node.manifest_digest == attributes.manifest_digest
  end

  defp classify(%Ash.Error.Invalid{}), do: {:error, :invalid_input}
  defp classify(%Ash.Error.Forbidden{}), do: {:error, :forbidden}
  defp classify(_error), do: {:error, :temporarily_unavailable}

  defp stored_envelope(envelope) do
    %{
      "method" => envelope.method,
      "path" => envelope.path,
      "headers" => envelope.headers,
      "body" => envelope.body
    }
  end
end
