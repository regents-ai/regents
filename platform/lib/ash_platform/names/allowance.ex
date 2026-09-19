defmodule AshPlatform.Names.Allowance do
  @moduledoc """
  The free claims a wallet was granted at the snapshot, and how many it has
  used. Storage is imported independently into regent_names; this resource
  never generates or replays migrations and has no write actions. Ownership is
  the site's own sign-in: a wallet that sign-in verified for the signed-in
  person.
  """
  use Ash.Resource,
    domain: AshPlatform.Names,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo(AshPlatform.Repo)
    schema("regent_names")
    table "basenames_mint_allowances"
    migrate?(false)
  end

  attributes do
    attribute :parent_node, :string, primary_key?: true, allow_nil?: false
    attribute :address, :string, primary_key?: true, allow_nil?: false, sensitive?: true
    attribute :parent_name, :string, allow_nil?: false
    attribute :snapshot_block_number, :integer, allow_nil?: false
    attribute :snapshot_total, :integer, allow_nil?: false, sensitive?: true
    attribute :free_mints_used, :integer, allow_nil?: false, sensitive?: true
    attribute :created_at, :utc_datetime_usec, allow_nil?: false
    attribute :updated_at, :utc_datetime_usec, allow_nil?: false
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
