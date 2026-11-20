defmodule Regents.Patchbay.Offers.Settlement do
  @moduledoc """
  One `LeaseSettled` event of Patchbay's market, exactly as the chain gave it,
  never rewritten: a lease that ended (bought out, run out or terminated) and
  how what it paid was split between the buyer's refund, the publisher and the
  protocol fee. The three add up to what the lease paid.

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
    table("agent_offer_settlements")
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
    attribute(:nonce, :integer, allow_nil?: false, public?: true, constraints: [min: 1])

    attribute(:reason, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:bought_out, :expired, :terminated]]
    )

    attribute(:settled_at, :utc_datetime, allow_nil?: false, public?: true)
    # USDC base units (six decimals), as the event carried them.
    attribute(:refund_usdc, :decimal, allow_nil?: false, public?: true, constraints: [min: 0])
    attribute(:publisher_usdc, :decimal, allow_nil?: false, public?: true, constraints: [min: 0])
    attribute(:fee_usdc, :decimal, allow_nil?: false, public?: true, constraints: [min: 0])

    create_timestamp(:inserted_at)
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
