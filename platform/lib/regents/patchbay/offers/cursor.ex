defmodule Regents.Patchbay.Offers.Cursor do
  @moduledoc """
  How far Patchbay's market has been read on its chain, always at the latest
  block: the first block not read yet, and the head last seen and when.
  Reading never stops: where the chain disagrees with the record, the reader
  keeps what it saved first and reads on.

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
    table("agent_offer_cursors")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:chain_id, :integer, allow_nil?: false, public?: true, constraints: [min: 1])
    attribute(:market, :string, allow_nil?: false, public?: true, constraints: [match: @address])
    # The first block not read yet.
    attribute(:next_block, :integer, allow_nil?: false, public?: true, constraints: [min: 0])
    attribute(:head_block, :integer, public?: true, constraints: [min: 0])
    attribute(:head_block_hash, :string, public?: true, constraints: [match: @hash])
    attribute(:observed_at, :utc_datetime_usec, public?: true)

    timestamps()
  end

  identities do
    identity(:unique_cursor, [:chain_id, :market])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
