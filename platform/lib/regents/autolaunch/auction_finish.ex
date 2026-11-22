defmodule Regents.Autolaunch.AuctionFinish do
  @moduledoc """
  One launch on a launchpad this site describes, and whether its auction has
  been finished.

  An auction does not finish itself. Once its migration block has passed,
  someone has to call `migrate`, which either graduates the launch (pool,
  locked liquidity, vesting) or fails it (bids become refundable). Anyone may
  call it. Every `migrate` sent is an `AuctionFinish.Transaction`, recorded
  before it is broadcast, and a launch is sent another only once the chain has
  settled the last.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "auction_finishes"
    schema("autolaunch_app")
    repo(Regents.Repo)

    identity_index_names(one_per_launch: "auction_finishes_launch_index")
  end

  attributes do
    uuid_primary_key :id

    attribute :launchpad, :atom,
      allow_nil?: false,
      constraints: [one_of: [:base_revstake, :base_memestock, :robinhood_memestock]]

    attribute :chain_id, :integer, allow_nil?: false, constraints: [min: 1]

    # The contract that numbers the launches: the Revstake factory, or the
    # Memestock launchpad.
    attribute :contract, :string,
      allow_nil?: false,
      constraints: [min_length: 42, max_length: 42]

    attribute :launch_id, :integer, allow_nil?: false, constraints: [min: 1]

    attribute :auction, :string,
      allow_nil?: false,
      constraints: [min_length: 42, max_length: 42]

    attribute :migration_block, :integer, allow_nil?: false, constraints: [min: 0]

    attribute :state, :atom,
      allow_nil?: false,
      constraints: [one_of: [:running, :graduated, :failed]]

    timestamps()
  end

  identities do
    identity :one_per_launch, [:chain_id, :contract, :launch_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
