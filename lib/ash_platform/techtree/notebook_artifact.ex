defmodule AshPlatform.Techtree.NotebookArtifact do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Techtree,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :node_payload_hash, :string do
      allow_nil? false
      public? true
      constraints max_length: 128
    end

    attribute :source_hash, :string do
      allow_nil? false
      public? true
      constraints max_length: 80
    end

    attribute :payload_hash, :string do
      allow_nil? false
      public? true
      constraints max_length: 80
    end

    attribute :marimo_version, :string do
      allow_nil? false
      public? true
      constraints max_length: 32
    end

    attribute :runtime, :atom do
      allow_nil? false
      public? true
      default :pyodide
      constraints one_of: [:pyodide]
    end

    attribute :compatibility, :atom do
      allow_nil? false
      public? true
      default :verified
      constraints one_of: [:verified]
    end

    attribute :run_url, :string do
      allow_nil? false
      public? true
      constraints max_length: 2_048
    end

    attribute :manifest_json, :string do
      allow_nil? false
      constraints max_length: 524_288
    end

    attribute :allowed_assets, {:array, :string} do
      allow_nil? false
      public? true
      default []
      constraints max_length: 32, items: [max_length: 2_048]
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :node, AshPlatform.Techtree.Node do
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    create :import_verified do
      accept [
        :node_id,
        :node_payload_hash,
        :source_hash,
        :payload_hash,
        :marimo_version,
        :run_url,
        :manifest_json,
        :allowed_assets
      ]

      change AshPlatform.Techtree.NotebookArtifact.Changes.ValidateArtifact
    end

    read :current_for_node do
      argument :node_id, :uuid, allow_nil?: false
      argument :node_payload_hash, :string, allow_nil?: false

      filter expr(
               node_id == ^arg(:node_id) and
                 node_payload_hash == ^arg(:node_payload_hash)
             )

      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 1)
    end
  end

  policies do
    policy action(:current_for_node) do
      authorize_if always()
    end

    policy action(:import_verified) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_node_source, [:node_id, :node_payload_hash, :source_hash]
  end

  postgres do
    table "notebook_artifacts"
    schema("techtree")
    repo(AshPlatform.Repo)
  end
end
