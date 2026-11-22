defmodule Regents.Autolaunch.AuctionPricePoint do
  @moduledoc """
  Confirmed clearing prices an auction contract announced. The contract names
  a price whenever it records a block's checkpoint and whenever a bid raises
  the price within a block; `clock_block` is that block on the auction's own
  clock. `sold` is what the auction had raised by the end of that event's
  block. Derived from chain events like `Regents.Autolaunch.BidActivity`.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "auction_price_points"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id
    attribute :block_number, :integer, allow_nil?: false
    attribute :log_index, :integer, allow_nil?: false
    attribute :clock_block, :integer, allow_nil?: false
    # Whole currency per whole token.
    attribute :clearing_price, :decimal, allow_nil?: false, constraints: [min: 0]
    # Whole currency.
    attribute :sold, :decimal, allow_nil?: false, constraints: [min: 0]
  end

  relationships do
    belongs_to :auction, Regents.Autolaunch.Auction do
      allow_nil? false
    end
  end

  identities do
    identity :auction_event, [:auction_id, :block_number, :log_index]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
