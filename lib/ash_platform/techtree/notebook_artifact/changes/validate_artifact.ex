defmodule AshPlatform.Techtree.NotebookArtifact.Changes.ValidateArtifact do
  use Ash.Resource.Change

  alias AshPlatform.Techtree
  alias AshPlatform.Techtree.NotebookArtifact.Proof

  @proof_fields [
    :source_hash,
    :payload_hash,
    :marimo_version,
    :runtime,
    :compatibility,
    :run_url,
    :manifest_json,
    :allowed_assets
  ]

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with :ok <- validate_proof(changeset),
           :ok <- validate_node(changeset) do
        changeset
      else
        {:error, message} -> Ash.Changeset.add_error(changeset, message: message)
      end
    end)
  end

  defp validate_proof(changeset) do
    attributes = Map.new(@proof_fields, &{&1, Ash.Changeset.get_attribute(changeset, &1)})
    Proof.validate(attributes)
  end

  defp validate_node(changeset) do
    node_id = Ash.Changeset.get_attribute(changeset, :node_id)
    node_payload_hash = Ash.Changeset.get_attribute(changeset, :node_payload_hash)

    case Techtree.get_public_node(node_id) do
      {:ok, %{payload_hash: ^node_payload_hash}} -> :ok
      {:ok, _node} -> {:error, "Notebook does not match the node's current payload"}
      _result -> {:error, "Notebook does not belong to a public node"}
    end
  end
end
