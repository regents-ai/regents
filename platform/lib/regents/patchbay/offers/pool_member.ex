defmodule Regents.Patchbay.Offers.PoolMember do
  @moduledoc """
  One advertiser wallet on a pool's membership list
  (`Regents.Patchbay.Offers.Pool`). Adding a wallet already there leaves it as it is.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Offers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @address ~r/\A0x[0-9a-f]{40}\z/

  postgres do
    table("agent_offer_pool_members")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:pool, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:wallet, :string, allow_nil?: false, public?: true, constraints: [match: @address])
    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :pool, Regents.Patchbay.Offers.Pool do
      allow_nil?(false)
      public?(true)
    end
  end

  identities do
    identity(:unique_member, [:pool_id, :wallet])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
