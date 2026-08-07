defmodule AshPlatform.Techtree do
  use Ash.Domain,
    otp_app: :ash_platform

  @edge_resource Module.concat(__MODULE__, "Edge")

  resources do
    resource AshPlatform.Techtree.Tree do
      define :list_trees, action: :list_public

      define :get_tree_by_slug,
        action: :public_by_slug,
        args: [:slug],
        not_found_error?: false

      define :upsert_seed_tree,
        action: :upsert_seed_root,
        args: [:slug, :name, :description, :position]
    end

    resource AshPlatform.Techtree.Node do
      define :list_public_nodes, action: :list_public

      define :list_tree_nodes, action: :list_public_for_tree, args: [:tree_id]

      define :get_public_node,
        action: :public_by_id,
        args: [:id],
        not_found_error?: false

      define :import_public_node,
        action: :import_public,
        args: [:tree_id, :title, :summary, :payload_hash]

      define :update_node_layout,
        action: :update_layout,
        args: [:pos_x, :pos_y, :display_kind]
    end

    resource @edge_resource do
      define :list_tree_edges, action: :list_for_tree, args: [:tree_id]

      define :create_edge,
        action: :create,
        args: [:from_node_id, :to_node_id]
    end

    resource AshPlatform.Techtree.NotebookArtifact do
      define :import_notebook_artifact,
        action: :import_verified,
        args: [
          :node_id,
          :node_payload_hash,
          :source_hash,
          :payload_hash,
          :marimo_version,
          :run_url,
          :manifest_json,
          :allowed_assets
        ]

      define :import_agent_notebook_artifact,
        action: :import_agent_verified,
        args: [
          :node_id,
          :node_payload_hash,
          :source_hash,
          :payload_hash,
          :marimo_version,
          :run_url,
          :manifest_json,
          :allowed_assets
        ]

      define :list_current_notebook_artifacts,
        action: :current_for_node,
        args: [:node_id, :node_payload_hash]
    end

    resource AshPlatform.Techtree.EvidenceStateUpdate do
      define :append_evidence_state_update,
        action: :append,
        args: [:node_id, :status, :reason, :evidence_reference_ids, :siwa_envelope]

      define :latest_evidence_state_update,
        action: :latest_for_node,
        args: [:node_id]

      define :list_evidence_state_updates,
        action: :all_for_node,
        args: [:node_id]
    end
  end

  def ensure_seed_trees(opts \\ []) do
    actor = Keyword.get(opts, :actor)

    Enum.reduce_while(AshPlatform.Techtree.SeedTrees.all(), :ok, fn tree, :ok ->
      case upsert_seed_tree(
             tree.slug,
             tree.name,
             tree.description,
             tree.position,
             actor: actor
           ) do
        {:ok, _tree} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
