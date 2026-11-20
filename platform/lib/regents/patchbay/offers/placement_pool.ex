defmodule Regents.Patchbay.Offers.PlacementPool do
  @moduledoc """
  One pool Patchbay chose for a placement (`Regents.Patchbay.Offers.Pool`): the
  placement shows campaigns from its chosen pools, and any campaign Patchbay
  accepts while it has none. The placement is named as the
  market names it, by chain, market and placement id. Choosing a pool already
  chosen leaves it as it is.

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
    table("agent_offer_placement_pools")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:pool, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:chain_id, :integer, allow_nil?: false, public?: true, constraints: [min: 1])
    attribute(:market, :string, allow_nil?: false, public?: true, constraints: [match: @address])
    attribute(:placement_id, :integer, allow_nil?: false, public?: true, constraints: [min: 1])
    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :pool, Regents.Patchbay.Offers.Pool do
      allow_nil?(false)
      public?(true)
    end
  end

  identities do
    identity(:unique_choice, [:chain_id, :market, :placement_id, :pool_id])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
