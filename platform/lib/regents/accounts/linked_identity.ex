defmodule Regents.Accounts.LinkedIdentity do
  @moduledoc """
  A social account Privy verified for one human account, one per provider.

  `inserted_at` is when this subject was linked to this account: a later
  sign-in with the same subject leaves it, and linking a different subject for
  the provider resets it. `verified_at` is Privy's newest check of the link.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    create :upsert_verified do
      accept []

      argument :provider, :atom,
        allow_nil?: false,
        constraints: [one_of: [:x, :github, :farcaster, :ens, :world]]

      argument :subject, :string, allow_nil?: false
      argument :username, :string
      argument :display_name, :string
      argument :verified_at, :utc_datetime_usec, allow_nil?: false
      argument :metadata, :map, allow_nil?: false
      argument :human_account_id, :integer, allow_nil?: false

      change set_attribute(:provider, arg(:provider))
      change set_attribute(:subject, arg(:subject))
      change set_attribute(:username, arg(:username))
      change set_attribute(:display_name, arg(:display_name))
      change set_attribute(:verified_at, arg(:verified_at))
      change set_attribute(:metadata, arg(:metadata))
      change set_attribute(:human_account_id, arg(:human_account_id))

      upsert? true
      upsert_identity :unique_provider_per_account
      # Reached only for a subject new to the account: a first link for the
      # provider, or one that replaces the account's earlier subject, so
      # `inserted_at` is always when this subject was linked.
      upsert_fields [:subject, :username, :display_name, :verified_at, :metadata, :inserted_at]

      emit Regents.Accounts.Signals, :social_linked
    end

    # A sign-in that finds the same subject already linked to the account.
    update :refresh_verified do
      accept [:username, :display_name, :verified_at, :metadata]
      require_atomic? false
    end

    read :read_mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [provider: :asc])
    end

    read :for_account do
      argument :human_account_id, :integer, allow_nil?: false
      filter expr(human_account_id == ^arg(:human_account_id))
      prepare build(sort: [provider: :asc])
    end

    read :by_provider_subject do
      get? true
      argument :provider, :atom, allow_nil?: false
      argument :subject, :string, allow_nil?: false
      filter expr(provider == ^arg(:provider) and subject == ^arg(:subject))
    end

    # Each account's link to one provider made before a moment, such as the Points start.
    read :linked_before do
      argument :provider, :atom, allow_nil?: false
      argument :at, :utc_datetime_usec, allow_nil?: false
      filter expr(provider == ^arg(:provider) and inserted_at < ^arg(:at))
    end

    destroy :remove_verified do
      accept []
      require_atomic? false
    end
  end

  policies do
    policy action([
             :upsert_verified,
             :refresh_verified,
             :for_account,
             :by_provider_subject,
             :linked_before,
             :remove_verified
           ]) do
      authorize_if Regents.Checks.SystemActor
    end

    policy action(:read_mine) do
      authorize_if Regents.Accounts.Checks.HumanActor
    end
  end

  identities do
    identity :unique_provider_per_account, [:provider, :human_account_id]
    identity :unique_subject_per_provider, [:provider, :subject]
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:x, :github, :farcaster, :ens, :world]
    end

    attribute :subject, :string, allow_nil?: false
    attribute :username, :string, public?: true
    attribute :display_name, :string, public?: true
    attribute :verified_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :metadata, :map, allow_nil?: false, default: %{}
    timestamps()
  end

  relationships do
    belongs_to :human_account, Regents.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  postgres do
    table "linked_identities"
    repo(Regents.Repo)
  end
end
