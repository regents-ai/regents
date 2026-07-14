defmodule AshPlatform.Formation.Regent do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Formation,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints max_length: 63, match: ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    end

    attribute :display_name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 80, trim?: true
    end

    attribute :summary, :string do
      public? true
      constraints max_length: 500, trim?: true
    end

    attribute :avatar_url, :string do
      public? true

      constraints max_length: 2_048,
                  match:
                    ~r/\A(?:\/(?!\/)[^\s]*|https:\/\/[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::[0-9]{1,5})?(?:\/[^\s]*)?)\z/
    end

    timestamps()
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  actions do
    create :form_regent do
      accept [:slug, :display_name]
      change AshPlatform.Formation.Changes.AssignHumanAccount
    end

    read :my_regent do
      get? true
      filter expr(human_account_id == ^actor(:human_account_id))
    end

    read :public_by_slug do
      get? true
      argument :slug, :string, allow_nil?: false
      filter expr(slug == ^arg(:slug))
    end

    action :public_profile, :struct do
      constraints instance_of: AshPlatform.Formation.PublicRegentProfile
      allow_nil? true
      argument :slug, :string, allow_nil?: false
      run AshPlatform.Formation.Regent.Actions.ReadPublicProfile
    end

    update :update_profile do
      accept [:display_name, :summary, :avatar_url]
      atomic_upgrade_with :my_regent
    end
  end

  policies do
    policy action(:public_by_slug) do
      authorize_if always()
    end

    policy action(:public_profile) do
      authorize_if always()
    end

    policy action([:form_regent, :my_regent, :update_profile]) do
      authorize_if AshPlatform.Formation.Checks.HumanActor
    end

    policy action(:my_regent) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    policy action(:update_profile) do
      authorize_if AshPlatform.Formation.Checks.RegentOwner
    end
  end

  identities do
    identity :unique_slug, [:slug]
    identity :unique_human_account, [:human_account_id]
  end

  postgres do
    table "regents"
    repo(AshPlatform.Repo)
  end
end
