defmodule Regents.Patchbay.Offers.Lease do
  @moduledoc """
  One `LeasePurchased` event of Patchbay's market, exactly as the chain gave
  it, never rewritten: a slot bought for one full term, by whom, for which
  campaign and for how much. A slot's lease with the highest nonce whose term
  has not run out is the one it shows, unless its placement was terminated.

  Its deliveries (`Regents.Patchbay.Offers.Delivery`) are the times Patchbay
  showed it.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Offers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @address ~r/\A0x[0-9a-f]{40}\z/
  @hash ~r/\A0x[0-9a-f]{64}\z/

  postgres do
    table("agent_offer_leases")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:chain_id, :integer, allow_nil?: false, public?: true, constraints: [min: 1])
    attribute(:market, :string, allow_nil?: false, public?: true, constraints: [match: @address])

    attribute(:transaction_hash, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: @hash]
    )

    attribute(:log_index, :integer, allow_nil?: false, public?: true, constraints: [min: 0])
    attribute(:block_number, :integer, allow_nil?: false, public?: true, constraints: [min: 0])
    attribute(:block_hash, :string, allow_nil?: false, public?: true, constraints: [match: @hash])

    attribute(:placement_id, :integer, allow_nil?: false, public?: true, constraints: [min: 1])
    attribute(:slot, :integer, allow_nil?: false, public?: true, constraints: [min: 0])
    attribute(:buyer, :string, allow_nil?: false, public?: true, constraints: [match: @address])

    attribute(:campaign_id, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: @hash]
    )

    # USDC base units (six decimals), as the event carried them.
    attribute(:paid_usdc, :decimal, allow_nil?: false, public?: true, constraints: [min: 0])
    attribute(:starts_at, :utc_datetime, allow_nil?: false, public?: true)
    attribute(:ends_at, :utc_datetime, allow_nil?: false, public?: true)
    attribute(:nonce, :integer, allow_nil?: false, public?: true, constraints: [min: 1])

    create_timestamp(:inserted_at)
  end

  relationships do
    has_many :deliveries, Regents.Patchbay.Offers.Delivery
  end

  identities do
    identity(:unique_chain_event, [:chain_id, :transaction_hash, :log_index])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
