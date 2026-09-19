defmodule AshPlatform.Names.PaymentCredit do
  @moduledoc """
  A paid claim a wallet bought and may still spend. Storage is imported
  independently into regent_names; this resource never generates or replays
  migrations and has no write actions. Ownership is the site's own sign-in: a
  wallet that sign-in verified for the signed-in person.
  """
  use Ash.Resource,
    domain: AshPlatform.Names,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo(AshPlatform.Repo)
    schema("regent_names")
    table "basenames_payment_credits"
    migrate?(false)
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false
    attribute :parent_node, :string, allow_nil?: false
    attribute :parent_name, :string, allow_nil?: false
    attribute :address, :string, allow_nil?: false, sensitive?: true
    attribute :payment_tx_hash, :string, allow_nil?: false, sensitive?: true
    attribute :payment_chain_id, :integer, sensitive?: true
    attribute :price_wei, :integer, allow_nil?: false, sensitive?: true
    attribute :consumed_at, :utc_datetime_usec
    attribute :consumed_node, :string
    attribute :consumed_fqdn, :string
    attribute :created_at, :utc_datetime_usec, allow_nil?: false
  end

  actions do
    read :mine do
      primary? true
    end
  end

  policies do
    policy action(:mine) do
      authorize_if AshPlatform.Accounts.Checks.HumanActor
    end

    policy action(:mine) do
      authorize_if expr(fragment("lower(?)", address) in ^actor(:wallet_addresses))
    end
  end
end
