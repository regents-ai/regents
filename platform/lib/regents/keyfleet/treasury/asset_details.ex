defmodule Regents.Keyfleet.Treasury.AssetDetails do
  @moduledoc """
  The symbol and decimals a token of a fleet's budget or payment proposals
  reports, read by `Regents.Keyfleet.Chain.TreasuryReader`. Either is nil when the
  token does not answer it, or answers a symbol that is not short plain text,
  and its amounts are then shown in whole atomic units. Once both are known
  they never change; a budget token with either unknown is read again, and
  the new reading replaces it. Whatever the symbol, only the fleet's own USDC
  is shown without its address.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Treasury,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "treasury_asset_details"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:asset, "treasury_asset_details_asset_shape",
        check: "asset ~ '^0x[0-9a-f]{40}$'"
      )

      check_constraint(:decimals, "treasury_asset_details_decimals_range",
        check: "decimals BETWEEN 0 AND 255"
      )
    end
  end

  actions do
    defaults [:read]

    create :record do
      public? false
      accept [:fleet_id, :asset, :symbol, :decimals]

      # A token read in full is never read again; one read with its symbol
      # or decimals unknown may be read again, and the new reading is kept.
      upsert? true
      upsert_identity :unique_fleet_asset
      upsert_fields [:symbol, :decimals]
      upsert_condition expr(is_nil(symbol) or is_nil(decimals))
      return_skipped_upsert? true
    end

    read :of_fleet do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:record) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :asset, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    attribute :symbol, :string, public?: true, constraints: [trim?: false, max_length: 32]
    attribute :decimals, :integer, public?: true, constraints: [min: 0, max: 255]
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_fleet_asset, [:fleet_id, :asset]
  end
end
