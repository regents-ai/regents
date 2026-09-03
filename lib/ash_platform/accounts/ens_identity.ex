defmodule AshPlatform.Accounts.EnsIdentity do
  @moduledoc """
  The ENS name and avatar image Ethereum mainnet publishes for an account's wallet.

  This is a cache of public chain state, not identity evidence: the account's own
  protected row keeps the verified Privy identity and wallet, and this row only
  carries what a page needs to draw the name and picture the wallet already
  announces to everyone.
  """

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    create :put_resolved do
      accept []
      argument :human_account_id, :integer, allow_nil?: false
      argument :ens_name, :string
      argument :ens_avatar_url, :string

      change set_attribute(:human_account_id, arg(:human_account_id))
      change set_attribute(:ens_name, arg(:ens_name))
      change set_attribute(:ens_avatar_url, arg(:ens_avatar_url))

      upsert? true
      upsert_identity :unique_human_account
      upsert_fields [:ens_name, :ens_avatar_url]
    end

    read :read do
      primary? true
    end
  end

  policies do
    policy action(:put_resolved) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    # Chain state anyone can read for themselves, so the account it belongs to
    # is what protects it, not this row.
    policy action(:read) do
      authorize_if always()
    end
  end

  identities do
    identity :unique_human_account, [:human_account_id]
  end

  attributes do
    uuid_primary_key :id
    attribute :ens_name, :string, public?: true
    attribute :ens_avatar_url, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  postgres do
    table "account_ens_identities"
    repo(AshPlatform.Repo)
  end
end
