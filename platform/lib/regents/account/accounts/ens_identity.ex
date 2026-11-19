defmodule Regents.Account.Accounts.EnsIdentity do
  @moduledoc """
  The ENS name and avatar image Ethereum mainnet publishes for an account's wallet.

  This is a cache of public chain state, not identity evidence: the account's own
  protected row keeps the verified Privy identity and wallet, and this row only
  carries what a page needs to draw the name and picture the wallet already
  announces to everyone.

  `wallet_address` is the wallet the row was read for. The account shows the
  name and picture only while that is still its own wallet
  (`Regents.Account.Accounts.HumanAccount`'s `ens_name` and `ens_avatar_url`), so an
  account whose wallet changed shows neither until its new wallet's lookup
  answers. A row recorded before the wallet was kept has none and shows nothing
  until the next lookup.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Account.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    create :put_resolved do
      accept []
      argument :human_account_id, :integer, allow_nil?: false
      argument :wallet_address, :string, allow_nil?: false
      argument :ens_name, :string
      argument :ens_avatar_url, :string

      change set_attribute(:human_account_id, arg(:human_account_id))
      change set_attribute(:wallet_address, arg(:wallet_address))
      change set_attribute(:ens_name, arg(:ens_name))
      change set_attribute(:ens_avatar_url, arg(:ens_avatar_url))

      upsert? true
      upsert_identity :unique_human_account
      upsert_fields [:wallet_address, :ens_name, :ens_avatar_url]

      # The row is written only for the wallet the account signs with now, so
      # an answer that finishes after the wallet changed is dropped. An answer
      # the same as the recorded one for that wallet, an absent name or picture
      # included, leaves the row and its update time as they are. Either way
      # the row comes back marked `upsert_skipped`, so the pages showing it are
      # not told to read it again.
      upsert_condition expr(
                         exists(human_account, wallet_address == upsert_conflict(:wallet_address)) and
                           (is_distinct_from(wallet_address, upsert_conflict(:wallet_address)) or
                              is_distinct_from(ens_name, upsert_conflict(:ens_name)) or
                              is_distinct_from(ens_avatar_url, upsert_conflict(:ens_avatar_url)))
                       )

      return_skipped_upsert? true
    end

    read :read do
      primary? true
    end
  end

  policies do
    policy action(:put_resolved) do
      authorize_if Regents.Checks.SystemActor
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
    attribute :wallet_address, :string, sensitive?: true
    attribute :ens_name, :string, public?: true
    attribute :ens_avatar_url, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :human_account, Regents.Account.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
      read_action :ens_identity_owner
    end
  end

  postgres do
    table "account_ens_identities"
    repo(Regents.Repo)
  end
end
