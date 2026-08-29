defmodule AshPlatform.Autolaunch.LaunchDraftImage.Changes.AssignOwner do
  @moduledoc false
  use Ash.Resource.Change

  alias AshPlatform.Actors.Human

  @impl true
  def change(changeset, _opts, %{actor: %Human{human_account_id: id}}) when is_integer(id) do
    Ash.Changeset.change_attribute(changeset, :human_account_id, id)
  end

  def change(changeset, _opts, _context), do: changeset
end

defmodule AshPlatform.Autolaunch.LaunchDraftImage do
  @moduledoc """
  One immutable image uploaded by a signed-in launch creator.

  Bytes never change or disappear after a URL has been issued. Owner reads are
  private; the only public read requires both the unguessable UUID and the full
  SHA-256 digest carried by the content-addressed URL.
  """

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :digest, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\A[0-9a-f]{64}\z/, max_length: 64
    end

    attribute :content_type, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\Aimage\/(png|jpeg|webp)\z/
    end

    attribute :byte_size, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 2_097_152
    end

    attribute :bytes, :binary do
      allow_nil? false
      sensitive? true
      select_by_default? false
    end

    timestamps()
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :unique_owner_digest, [:human_account_id, :digest]
  end

  actions do
    create :store_for_owner do
      accept [:digest, :content_type, :byte_size, :bytes]
      change AshPlatform.Autolaunch.LaunchDraftImage.Changes.AssignOwner
    end

    read :mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :mine_by_digest do
      get? true
      argument :digest, :string, allow_nil?: false
      filter expr(human_account_id == ^actor(:human_account_id) and digest == ^arg(:digest))
    end

    read :public_by_id_and_digest do
      get? true
      argument :id, :uuid, allow_nil?: false
      argument :digest, :string, allow_nil?: false
      filter expr(id == ^arg(:id) and digest == ^arg(:digest))
      prepare build(select: [:id, :digest, :content_type, :byte_size, :bytes])
    end
  end

  policies do
    policy action([:store_for_owner, :mine, :mine_by_digest]) do
      authorize_if AshPlatform.Formation.Checks.HumanActor
    end

    policy action([:mine, :mine_by_digest]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    policy action(:public_by_id_and_digest) do
      authorize_if always()
    end
  end

  postgres do
    table "launch_draft_images"
    schema("autolaunch")
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:human_account_id])
    end

    references do
      reference(:human_account, on_delete: :restrict)
    end
  end
end
