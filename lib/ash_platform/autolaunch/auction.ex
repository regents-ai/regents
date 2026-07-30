defmodule AshPlatform.Autolaunch.Auction do
  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 160, trim?: true
    end

    attribute :summary, :string do
      public? true
      constraints max_length: 2_000, trim?: true
    end

    attribute :featured, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :state, :atom do
      allow_nil? false
      public? true
      default :created
      constraints one_of: [:created, :active, :graduated, :failed]
    end

    attribute :opened_at, :utc_datetime_usec do
      public? true
    end

    attribute :auction_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    attribute :quote_token_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    attribute :quote_token_symbol, :string do
      public? true
      constraints min_length: 1, max_length: 32, trim?: true
    end

    attribute :quote_token_decimals, :integer do
      public? true
      constraints min: 0, max: 36
    end

    attribute :current_clearing_price, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    timestamps()
  end

  actions do
    read :read do
      primary? true
    end

    read :list_public do
      prepare build(sort: [inserted_at: :desc, id: :asc])
    end

    read :recent_public do
      prepare build(sort: [inserted_at: :desc, id: :asc], limit: 12)
    end

    read :featured_public do
      filter expr(featured == true)
      prepare build(sort: [inserted_at: :desc, id: :asc], limit: 6)
    end

    read :public_by_id do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    create :import_public do
      accept [:title, :summary, :featured, :state, :opened_at]
    end

    update :set_bid_terms do
      require_atomic? false

      accept [
        :auction_address,
        :quote_token_address,
        :quote_token_symbol,
        :quote_token_decimals,
        :current_clearing_price
      ]
    end
  end

  policies do
    policy action([:read, :list_public, :recent_public, :featured_public, :public_by_id]) do
      authorize_if always()
    end

    policy action(:import_public) do
      authorize_if AshPlatform.Checks.SystemActor
    end

    policy action(:set_bid_terms) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  postgres do
    table "auctions"
    schema("autolaunch")
    repo(AshPlatform.Repo)
  end
end
