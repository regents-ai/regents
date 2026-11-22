defmodule Regents.Autolaunch.Bid do
  @moduledoc """
  One bid position on a Base auction, and where its settlement stands.

  `status` follows the auction's own record of the bid:

    * `:active` while bidding is open, and until its end block has passed;
    * `:returnable` once the end block has passed and the bid has not exited;
    * `:awaiting_claim` once it exited with tokens filled, before the claim block;
    * `:claimable` once it exited with tokens filled and the claim block has passed;
    * `:returned` once it exited with nothing filled (finished);
    * `:claimed` once its tokens have been claimed (finished).

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @statuses [:active, :returnable, :awaiting_claim, :claimable, :returned, :claimed]

  # A bid id occupies one URL-safe segment, the identifier format the route
  # catalog accepts.
  @bid_id_shape ~r/\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z/

  postgres do
    table "bids"
    schema("autolaunch_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:status, "bids_status_known",
        check:
          "status IN ('active', 'returnable', 'awaiting_claim', 'claimable', 'returned', 'claimed')",
        message: "is not a bid status"
      )
    end

    custom_indexes do
      index([:owner_address])
      index([:auction_id])
      index([:status])
    end
  end

  attributes do
    uuid_primary_key :id, public?: false

    attribute :bid_id, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 128, trim?: false, match: @bid_id_shape
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

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :active
      constraints one_of: @statuses
    end

    attribute :exited_at, :utc_datetime_usec do
      public? true
    end

    attribute :claimed_at, :utc_datetime_usec do
      public? true
    end

    attribute :auction_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    attribute :onchain_bid_id, :string do
      public? true
      constraints min_length: 1, max_length: 78, trim?: true, match: ~r/\A\d+\z/
    end

    # Settlement amounts, adopted from the auction's own `BidExited` and
    # `TokensClaimed` events: the currency returned (in the auction's currency
    # units), the launch tokens the bid filled, and the tokens claimed.
    attribute :currency_refunded, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :tokens_filled, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :tokens_claimed, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    timestamps()
  end

  relationships do
    belongs_to :auction, Regents.Autolaunch.Auction do
      allow_nil? false
      attribute_public? true
    end

    has_one :token, Regents.Autolaunch.Token do
      source_attribute :auction_id
      destination_attribute :auction_id
    end
  end

  identities do
    identity :unique_bid_id, [:bid_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
