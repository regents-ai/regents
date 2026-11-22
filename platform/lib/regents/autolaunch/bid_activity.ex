defmodule Regents.Autolaunch.BidActivity do
  @moduledoc """
  Confirmed public bid events, with the wallet that owns each bid. No pending
  transactions. `clock_block` is the block on the auction's own clock the bid
  landed in, which is what its start and end blocks count.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "bid_activity"
    schema("autolaunch_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:auction_id, :block_number])
      index(["occurred_at DESC", "id"], name: "bid_activity_recent_index")
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :bid_id, :string, allow_nil?: false
    # The wallet that owns the bid, lowercase.
    attribute :bidder, :string, allow_nil?: false
    attribute :transaction_hash, :string, allow_nil?: false
    attribute :block_hash, :string, allow_nil?: false
    attribute :block_number, :integer, allow_nil?: false
    attribute :log_index, :integer, allow_nil?: false
    attribute :clock_block, :integer, allow_nil?: false
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false
    attribute :amount, :decimal, allow_nil?: false, constraints: [min: 0]
    attribute :display_amount, :decimal, allow_nil?: false, constraints: [min: 0]
    attribute :display_symbol, :string, allow_nil?: false
    # The most the bid pays per token, in the auction's currency.
    attribute :max_price, :decimal, allow_nil?: false, constraints: [min: 0]
  end

  relationships do
    belongs_to :auction, Regents.Autolaunch.Auction do
      allow_nil? false
    end
  end

  identities do
    identity :auction_bid, [:auction_id, :bid_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
