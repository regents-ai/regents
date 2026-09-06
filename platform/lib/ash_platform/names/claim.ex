defmodule AshPlatform.Names.Claim do
  @moduledoc """
  All 23 columns of the retained claim table. Storage is imported independently
  into regent_names; this resource never generates or replays legacy migrations.
  Ownership is filtered in Ash from fresh verified wallet evidence, not account IDs.
  """
  use Ash.Resource,
    # The sole read intentionally orders historical evidence for cursor pagination.
    primary_read_warning?: false,
    domain: AshPlatform.Names,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo(AshPlatform.Repo)
    schema("regent_names")
    table "basenames_mints"
    migrate?(false)
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false
    attribute :parent_node, :string, allow_nil?: false
    attribute :parent_name, :string, allow_nil?: false
    attribute :label, :string, allow_nil?: false
    attribute :fqdn, :string, allow_nil?: false
    attribute :node, :string, allow_nil?: false
    attribute :ens_fqdn, :string
    attribute :ens_node, :string
    attribute :owner_address, :string, allow_nil?: false, sensitive?: true
    attribute :tx_hash, :string, allow_nil?: false
    attribute :ens_tx_hash, :string
    attribute :ens_assigned_at, :utc_datetime_usec
    attribute :payment_tx_hash, :string, sensitive?: true
    attribute :payment_chain_id, :integer, sensitive?: true
    attribute :price_wei, :integer, sensitive?: true
    attribute :is_free, :boolean, allow_nil?: false, sensitive?: true
    attribute :is_in_use, :boolean, allow_nil?: false, sensitive?: true
    attribute :created_at, :utc_datetime_usec, allow_nil?: false
    attribute :claim_status, :string, allow_nil?: false
    attribute :upgrade_tx_hash, :string
    attribute :upgraded_at, :naive_datetime
    attribute :formation_agent_slug, :string, sensitive?: true
    attribute :attached_agent_slug, :string, sensitive?: true
  end

  actions do
    read :mine do
      primary? true
      prepare build(sort: [id: :asc])

      pagination do
        required? true
        keyset? true
        default_limit 50
        max_page_size 50
      end
    end
  end

  policies do
    policy action(:mine) do
      authorize_if AshPlatform.Names.VerifiedOwner
    end

    policy action(:mine) do
      authorize_if expr(fragment("lower(?)", owner_address) in ^actor(:wallet_addresses))
    end
  end
end
