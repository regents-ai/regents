defmodule Regents.Patchbay.Offers.Placement do
  @moduledoc """
  One `PlacementCreated` event of Patchbay's market, exactly as the chain gave
  it, never rewritten: a place on a site's page Patchbay sells, its slots,
  each lease's length, the step a buyout must pay over a live lease, the
  floor price, and the admission policy every purchase in it is signed under.

  `source_origin` is what the placement is for: a listed site, or General or
  CVE incidents. Patchbay's own placements name
  its page as their address (`metadata_uri`, ending in the site's address or
  the name), and it counts only when its hash is the placement's `source_id`,
  so the address cannot name a different one.

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
    table("agent_offer_placements")
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
    attribute(:source_id, :string, allow_nil?: false, public?: true, constraints: [match: @hash])
    attribute(:capacity, :integer, allow_nil?: false, public?: true, constraints: [min: 1])

    attribute(:duration_seconds, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]
    )

    attribute(:min_bump_bps, :integer, allow_nil?: false, public?: true, constraints: [min: 0])
    # USDC base units (six decimals), as the event carried them.
    attribute(:floor_usdc, :decimal, allow_nil?: false, public?: true, constraints: [min: 0])

    attribute(:policy_hash, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: @hash]
    )

    attribute(:metadata_uri, :string,
      allow_nil?: false,
      public?: true,
      constraints: [allow_empty?: true, trim?: false]
    )

    attribute(:source_origin, :string, allow_nil?: true, public?: true)

    create_timestamp(:inserted_at)
  end

  relationships do
    has_many :terminations, Regents.Patchbay.Offers.Termination do
      no_attributes?(true)
      validate_destination_attribute?(false)

      filter(
        expr(
          chain_id == parent(chain_id) and market == parent(market) and
            placement_id == parent(placement_id)
        )
      )
    end
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
