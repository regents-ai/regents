defmodule Regents.Accounts.HumanAccount do
  use Ash.Resource,
    domain: Regents.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "platform_human_users"
    schema("regent_names")
    repo(Regents.Repo)
    migrate?(false)
  end

  actions do
    read :by_privy_did do
      get? true
      argument :privy_did, :string, allow_nil?: false
      filter expr(privy_user_id == ^arg(:privy_did))
    end

    read :read_self do
      get? true
      argument :id, :integer, allow_nil?: false
      filter expr(id == ^arg(:id))
      prepare build(load: [:display_name, :ens_name, :ens_avatar_url, :ens_identity])
    end

    read :points_account do
      get? true
      argument :id, :integer, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    # The accounts made before a moment, such as the Points start.
    read :created_before do
      argument :at, :utc_datetime_usec, allow_nil?: false
      filter expr(created_at < ^arg(:at))
    end

    read :by_privy_dids do
      argument :privy_dids, {:array, :string}, allow_nil?: false
      filter expr(privy_user_id in ^arg(:privy_dids))
    end

    # The accounts the Points board lists, with what shows of them to others.
    read :points_people do
      argument :ids, {:array, :integer}, allow_nil?: false
      filter expr(id in ^arg(:ids))
      prepare build(load: [:display_name, :ens_name, :ens_avatar_url])
    end

    read :public_profile_source do
      public? false
      get? true
      argument :id, :integer, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    create :register_verified do
      accept []
      argument :privy_did, :string, allow_nil?: false
      argument :wallet_address, :string
      argument :wallet_addresses, {:array, :string}
      change set_attribute(:privy_user_id, arg(:privy_did))
      change set_attribute(:wallet_address, arg(:wallet_address))
      change set_attribute(:wallet_addresses, arg(:wallet_addresses))
      upsert? true
      upsert_identity :unique_privy_user_id
      # A sign-in to an existing account writes nothing to it, and the account
      # comes back marked as skipped.
      upsert_condition expr(false)
      return_skipped_upsert? true

      emit Regents.Accounts.Signals, :account_registered,
        dynamic?: true,
        description: "Only when the sign-in inserted the account."

      change Regents.Accounts.HumanAccount.AnnounceRegistration
    end

    # The sign-in answers with the account's menu, which shows its name.
    update :refresh_verified do
      accept []
      require_atomic? false
      argument :wallet_address, :string
      argument :wallet_addresses, {:array, :string}
      change Regents.Accounts.Changes.RefreshWalletEvidence
      change load([:display_name])
    end
  end

  policies do
    policy actor_attribute_equals(:role, :agent) do
      forbid_unless {RegentAgents.Checks.Paired, repo: Regents.Repo}
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end

    policy action([
             :by_privy_did,
             :register_verified,
             :refresh_verified,
             :public_profile_source,
             :points_account,
             :created_before,
             :by_privy_dids,
             :points_people
           ]) do
      authorize_if Regents.Checks.SystemActor
    end

    policy action(:read_self) do
      authorize_if expr(id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :unique_privy_user_id, [:privy_user_id]
    identity :unique_world_human_id, [:world_human_id]
  end

  attributes do
    integer_primary_key :id
    attribute :privy_user_id, :string, allow_nil?: false, sensitive?: true
    attribute :wallet_address, :string, sensitive?: true
    attribute :wallet_addresses, {:array, :string}, default: [], sensitive?: true
    attribute :world_human_id, :string, sensitive?: true
    attribute :world_verified_at, :utc_datetime
    attribute :avatar, :map
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_one :ens_identity, Regents.Accounts.EnsIdentity do
      destination_attribute :human_account_id
    end
  end

  calculations do
    # The name set in the person's shared Regent profile.
    calculate :display_name, :string, {RegentIdentity.ProfileName, otp_app: :regents},
      public?: true

    # What Ethereum mainnet says about this account's wallet, flattened onto the
    # account so one display shape serves every identity a page renders.
    calculate :ens_name, :string, expr(ens_identity.ens_name)
    calculate :ens_avatar_url, :string, expr(ens_identity.ens_avatar_url)
  end
end
