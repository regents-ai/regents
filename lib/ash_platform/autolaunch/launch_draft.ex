defmodule AshPlatform.Autolaunch.LaunchDraft do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @token_fields [
    :name,
    :symbol,
    :description,
    :website,
    :image,
    :required_regent_raised
  ]

  @treasury_fields [
    :treasury,
    :treasury_path,
    :eoa_acknowledgement
  ]

  @clean_v1_fields @token_fields ++ @treasury_fields

  @eoa_acknowledgement "This auction will be owned by my EOA private key, and significant harm and token value will happen if it is lost or compromised. I was warned to create a Gnosis Safe or 0xSplits smart account as the owner, and I realize auction bidders and token owners will see that it is EOA-owned and more risky. I accept these problems, and wish to continue with EOA ownership of the token."

  @metadata_limits [name: 64, symbol: 16, description: 512, website: 256, image: 256]
  @address ~r/\A0x[0-9a-fA-F]{40}\z/
  @zero_address "0x" <> String.duplicate("0", 40)
  @amount ~r/\A[0-9]+(\.[0-9]{1,18})?\z/

  @doc "Whether the persisted token metadata stage is ready for launch review."
  def token_details_complete?(draft) do
    Enum.all?(@metadata_limits, fn {field, limit} ->
      value = Map.get(draft, field)
      is_binary(value) and value != "" and String.valid?(value) and byte_size(value) <= limit
    end) and valid_raise?(Map.get(draft, :required_regent_raised))
  end

  @doc "Whether the persisted treasury stage is ready for launch review."
  def treasury_complete?(draft) do
    treasury = Map.get(draft, :treasury)
    path = Map.get(draft, :treasury_path)

    is_binary(treasury) and Regex.match?(@address, treasury) and
      String.downcase(treasury) != @zero_address and path in [:safe, :contract, :eoa] and
      (path != :eoa or Map.get(draft, :eoa_acknowledgement) == @eoa_acknowledgement)
  end

  @doc "Whether both persisted preparation stages are complete."
  def launch_ready?(draft), do: token_details_complete?(draft) and treasury_complete?(draft)

  defp valid_raise?(value) when is_binary(value),
    do: Regex.match?(@amount, value) and Regex.match?(~r/[1-9]/, value)

  defp valid_raise?(_value), do: false

  attributes do
    uuid_primary_key :id

    # Superseded launch-page title. It is never read or written by the current
    # route; it exists only so rows written before clean V1 stay intact.
    attribute :title, :string

    attribute :name, :string do
      source :token_name
      allow_nil? false
      default ""
      public? true
      constraints allow_empty?: true
    end

    attribute :symbol, :string do
      allow_nil? false
      default ""
      public? true
      constraints allow_empty?: true
    end

    attribute :description, :string do
      source :summary
      public? true
    end

    attribute :website, :string, public?: true
    attribute :image, :string, public?: true
    attribute :treasury, :string, public?: true

    attribute :treasury_path, :atom do
      allow_nil? false
      public? true
      default :safe
      constraints one_of: [:safe, :eoa, :contract]
    end

    attribute :required_regent_raised, :string, public?: true

    attribute :eoa_acknowledgement, :string do
      public? true
      constraints max_length: 512, trim?: false
    end

    timestamps()
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    belongs_to :regent, AshPlatform.Formation.Regent do
      # Historical drafts retain their former relationship. New drafts belong
      # directly to the signed-in Human and never invent Regent provenance.
      allow_nil? true
    end

    belongs_to :launch_draft_image, AshPlatform.Autolaunch.LaunchDraftImage do
      allow_nil? true
    end
  end

  actions do
    create :create_for_owner do
      accept @clean_v1_fields
      change AshPlatform.Autolaunch.LaunchDraft.Changes.EnsurePartialDefaults
      validate AshPlatform.Autolaunch.LaunchDraft.Validations.PartialFields
      change AshPlatform.Autolaunch.LaunchDraft.Changes.AssignOwner
    end

    read :mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [updated_at: :desc, id: :asc])
    end

    read :mine_by_id do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(human_account_id == ^actor(:human_account_id) and id == ^arg(:id))
    end

    read :mine_by_id_for_update do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(human_account_id == ^actor(:human_account_id) and id == ^arg(:id))

      prepare fn query, _context -> Ash.Query.lock(query, :for_update) end
    end

    update :autosave_token_details do
      accept @token_fields
      require_atomic? false
      validate AshPlatform.Autolaunch.LaunchDraft.Validations.PartialFields
    end

    update :autosave_treasury do
      accept @treasury_fields
      require_atomic? false
      validate AshPlatform.Autolaunch.LaunchDraft.Validations.PartialFields
    end

    update :attach_image do
      argument :launch_draft_image_id, :uuid, allow_nil?: false
      require_atomic? false
      change AshPlatform.Autolaunch.LaunchDraft.Changes.AttachOwnedImage
    end

    update :revise_by_owner do
      accept @clean_v1_fields
      require_atomic? false
      validate AshPlatform.Autolaunch.LaunchDraft.Validations.CleanV1Fields

      validate attribute_equals(:eoa_acknowledgement, @eoa_acknowledgement),
        where: [attribute_equals(:treasury_path, :eoa)]
    end
  end

  policies do
    policy action([
             :create_for_owner,
             :mine,
             :mine_by_id,
             :mine_by_id_for_update,
             :autosave_token_details,
             :autosave_treasury,
             :attach_image,
             :revise_by_owner
           ]) do
      authorize_if AshPlatform.Formation.Checks.HumanActor
    end

    policy action([
             :mine,
             :mine_by_id,
             :mine_by_id_for_update,
             :autosave_token_details,
             :autosave_treasury,
             :attach_image,
             :revise_by_owner
           ]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  postgres do
    table "launch_drafts"
    schema("autolaunch")
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:human_account_id])
      index([:regent_id])
      index([:launch_draft_image_id])
    end
  end
end
