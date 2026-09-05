defmodule RegentIdentity.Profile do
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
    attribute :display_name, :string, constraints: [max_length: 80]
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
    policy always() do
      authorize_if RegentIdentity.VerifiedActor
    end

    policy action([:mine, :refresh, :edit]) do
      authorize_if expr(app_id == ^actor(:app_id) and privy_user_id == ^actor(:privy_user_id))
    end
  end
end
