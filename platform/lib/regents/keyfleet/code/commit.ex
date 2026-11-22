defmodule Regents.Keyfleet.Code.Commit do
  @moduledoc """
  The push that first sent each commit to a project's repository, so a page
  names who sent any commit, not only a branch's new tip
  (`Regents.Keyfleet.Code.Sent`). A commit's git author is whatever its writer typed;
  the push names the Key, and the agent when one sent it. Read as the code
  is, by the fleet's members (`Regents.Keyfleet.Access`, `:code`), and gone with the
  push it came with.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Code,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "code_commits"
    schema("keyfleet_app")
    repo(Regents.Repo)

    references do
      reference(:push, on_delete: :delete, index?: true)
    end
  end

  identities do
    identity :commit, [:fleet_id, :project, :hash]
  end

  actions do
    # A commit sent again, on another branch or by another push, keeps the
    # push that sent it first.
    create :record do
      accept [:fleet_id, :project, :hash, :push_id]
      upsert? true
      upsert_identity :commit
      upsert_fields [:hash]
    end

    read :of_hashes do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      argument :hashes, {:array, :string}, allow_nil?: false, constraints: [max_length: 100]

      filter expr(
               fleet_id == ^arg(:fleet_id) and project == ^arg(:project) and
                 hash in ^arg(:hashes)
             )
    end
  end

  policies do
    policy action(:of_hashes) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :code, scope: :fleet_id}
    end

    policy action(:record) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :fleet_id, :string, allow_nil?: false, public?: true
    attribute :project, :string, allow_nil?: false, public?: true
    attribute :hash, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :push, Regents.Keyfleet.Code.Push, allow_nil?: false
  end
end
