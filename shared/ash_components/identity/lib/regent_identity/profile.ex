defmodule RegentIdentity.Profile do
  @moduledoc """
  One shared profile per Privy account: display name, selected wallet, the
  verified linked wallets and X account, and when that proof was issued.
  """
  use Ash.Resource,
    domain: RegentIdentity,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentIdentity.repo/2
    schema "regent_identity"
    table "profiles"
    migrate? false
  end

  attributes do
    uuid_primary_key :id
    attribute :app_id, :string, allow_nil?: false, sensitive?: true
    attribute :privy_user_id, :string, allow_nil?: false, sensitive?: true
    # A name shows on every Regent site, so it holds no hidden characters.
    attribute :display_name, :string,
      constraints: [max_length: 80, match: RegentFormat.Name.pattern()]

    attribute :wallet_address, :string, sensitive?: true

    attribute :wallet_addresses, {:array, :string},
      allow_nil?: false,
      default: [],
      sensitive?: true

    attribute :x_subject, :string, sensitive?: true
    attribute :x_username, :string
    attribute :x_display_name, :string
    attribute :proof_issued_at, :integer, allow_nil?: false, sensitive?: true
    timestamps()
  end

  identities do
    identity :privy_subject, [:app_id, :privy_user_id]
    identity :x_subject_owner, [:app_id, :x_subject]
  end

  actions do
    read :mine do
      get? true
      filter expr(app_id == ^actor(:app_id) and privy_user_id == ^actor(:privy_user_id))
    end

    # Only `RegentIdentity.ProfileName` reads this, unauthorized: names are
    # public, and it selects nothing but the name.
    read :names do
      argument :app_id, :string, allow_nil?: false
      argument :privy_user_ids, {:array, :string}, allow_nil?: false
      filter expr(app_id == ^arg(:app_id) and privy_user_id in ^arg(:privy_user_ids))
    end

    # Only `RegentIdentity.profile_id/2` reads this, unauthorized, and it
    # selects nothing but the ID.
    read :person do
      get? true
      argument :app_id, :string, allow_nil?: false
      argument :privy_user_id, :string, allow_nil?: false
      filter expr(app_id == ^arg(:app_id) and privy_user_id == ^arg(:privy_user_id))
    end

    create :register do
      accept []
      change RegentIdentity.ProofAttributes
    end

    update :refresh do
      accept []
      require_atomic? false
      change RegentIdentity.ProofAttributes
    end

    update :edit do
      accept [:display_name, :wallet_address]
      require_atomic? false
      change RegentIdentity.SelectedWallet
    end
  end

  policies do
    # A current verified Privy sign-in makes or refreshes its own profile.
    policy action([:register, :refresh]) do
      authorize_if RegentIdentity.VerifiedActor
    end

    # The owner the site resolved reads and changes their own profile.
    policy action([:mine, :edit]) do
      authorize_if RegentIdentity.OwnerActor
    end

    policy action([:mine, :refresh, :edit]) do
      authorize_if expr(app_id == ^actor(:app_id) and privy_user_id == ^actor(:privy_user_id))
    end

    # Only the library reads these, unauthorized: `RegentIdentity.ProfileName`
    # for names and `RegentIdentity.profile_id/2` for a person's profile ID.
    policy action([:names, :person]) do
      forbid_if always()
    end
  end
end
