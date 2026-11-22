defmodule Regents.Autolaunch.LaunchDraftImage do
  @moduledoc """
  One immutable image uploaded by a signed-in launch creator.

  Bytes never change or disappear after a URL has been issued. Owner reads are
  private; the only public read requires both the unguessable UUID and the full
  SHA-256 digest carried by the content-addressed URL.

  The table and its rows as autolaunch.sh keeps them; the public read is the only
  action here (`Regents.Autolaunch.StoredImage`), and nothing writes a row.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "launch_draft_images"
    schema("autolaunch_app")
    repo(Regents.Repo)

    references do
      reference(:human_account, on_delete: :restrict)
      reference(:launch_draft, on_delete: :restrict)
    end
  end

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

    attribute :color, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\A#[0-9a-f]{6}\z/, max_length: 7
    end

    attribute :bytes, :binary do
      allow_nil? false
      sensitive? true
      select_by_default? false
    end

    attribute :original_filename, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255
    end

    timestamps()
  end

  relationships do
    belongs_to :human_account, Regents.Account.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    belongs_to :launch_draft, Regents.Autolaunch.LaunchDraft do
      allow_nil? false
    end
  end

  identities do
    identity :one_version_per_draft, [:launch_draft_id, :digest]
  end

  actions do
    read :public_by_id_and_digest do
      get? true
      argument :id, :uuid, allow_nil?: false
      argument :digest, :string, allow_nil?: false
      filter expr(id == ^arg(:id) and digest == ^arg(:digest))
      prepare build(select: [:id, :digest, :content_type, :byte_size, :bytes])
    end
  end

  # Anyone may read a picture by its address; any other action has no policy and
  # is refused.
  policies do
    policy action(:public_by_id_and_digest) do
      authorize_if always()
    end
  end
end
