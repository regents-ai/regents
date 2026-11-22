defmodule Regents.Autolaunch.BidSettlement do
  @moduledoc """
  Confirmed public withdraws and claims: each auction's own `BidExited` and
  `TokensClaimed` events, whoever sent them. No pending transactions.

  A withdraw states the auction currency that came back and the launch tokens
  the bid filled; a claim states the tokens it delivered.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "bid_settlements"
    schema("autolaunch_app")
    repo(Regents.Repo)

    # The chain position identity's unique index serves the watcher's range
    # deletes; this one serves a bid's own page.
    custom_indexes do
      index([:auction_id, :bid_id])
    end
  end

  attributes do
    uuid_primary_key :id
    # The auction's own id for the bid.
    attribute :bid_id, :string, allow_nil?: false, public?: true

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:exit, :claim]
    end

    # The wallet that owns the bid, lowercase.
    attribute :owner, :string, allow_nil?: false, public?: true
    attribute :transaction_hash, :string, allow_nil?: false, public?: true
    attribute :block_hash, :string, allow_nil?: false
    attribute :block_number, :integer, allow_nil?: false
    attribute :log_index, :integer, allow_nil?: false
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false, public?: true
    # A withdraw's currency returned, in the auction's currency; nil on a claim.
    attribute :currency, :decimal, public?: true, constraints: [min: 0]
    # A withdraw's tokens filled, or a claim's tokens delivered.
    attribute :tokens, :decimal, allow_nil?: false, public?: true, constraints: [min: 0]
  end

  relationships do
    belongs_to :auction, Regents.Autolaunch.Auction do
      allow_nil? false
    end
  end

  identities do
    identity :chain_position, [:auction_id, :block_number, :log_index]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
