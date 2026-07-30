defmodule AshPlatform.Autolaunch.Bid do
  alias AshPlatform.Autolaunch.BidIdentity

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id, public?: false

    attribute :bid_id, :string do
      allow_nil? false
      public? true
      constraints BidIdentity.constraints()
    end

    attribute :owner_address, :string do
      allow_nil? false
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    attribute :amount, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :max_price, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :current_clearing_price, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :estimated_tokens_if_end_now, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :status, :string do
      allow_nil? false
      public? true
      default "active"
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :exited_at, :utc_datetime_usec do
      public? true
    end

    attribute :claimed_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :auction, AshPlatform.Autolaunch.Auction do
      allow_nil? false
      attribute_public? true
    end

    has_one :token, AshPlatform.Autolaunch.Token do
      source_attribute :auction_id
      destination_attribute :auction_id
    end
  end

  actions do
    read :mine do
      prepare build(sort: [inserted_at: :desc, id: :desc], load: [:auction, :token])
    end

    read :returnable_mine do
      filter expr(status == "returnable")

      prepare build(
                sort: [updated_at: :desc, inserted_at: :desc, id: :desc],
                load: [:auction, :token]
              )
    end

    read :claimed_mine do
      filter expr(status == "claimed")

      prepare build(
                sort: [claimed_at: :desc_nils_last, inserted_at: :desc, id: :desc],
                load: [:auction, :token]
              )
    end

    create :import_position do
      accept [
        :bid_id,
        :auction_id,
        :owner_address,
        :amount,
        :max_price,
        :current_clearing_price,
        :estimated_tokens_if_end_now,
        :status,
        :exited_at,
        :claimed_at
      ]

      change AshPlatform.Autolaunch.Bid.Changes.NormalizeOwnerAddress
    end
  end

  policies do
    policy action([:mine, :returnable_mine, :claimed_mine]) do
      authorize_if AshPlatform.Formation.Checks.HumanActor
    end

    policy action([:mine, :returnable_mine, :claimed_mine]) do
      authorize_if AshPlatform.Autolaunch.Bid.Checks.VerifiedWalletOwner
    end

    policy action(:import_position) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_bid_id, [:bid_id]
  end

  postgres do
    table "bids"
    schema("autolaunch")
    repo(AshPlatform.Repo)

    custom_indexes do
      index([:owner_address])
      index([:auction_id])
      index([:status])
    end
  end
end
