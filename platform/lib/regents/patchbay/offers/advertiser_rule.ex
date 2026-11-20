defmodule Regents.Patchbay.Offers.AdvertiserRule do
  @moduledoc """
  Patchbay's word on one advertiser wallet: `:accepted` or `:blocked`. A
  wallet Patchbay has not accepted is not admitted to buy, and a blocked
  wallet never is, even if it is also accepted.

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
    table("agent_offer_advertiser_rules")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:wallet, :string, allow_nil?: false, public?: true, constraints: [match: @address])

    attribute(:verdict, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:accepted, :blocked]]
    )

    create_timestamp(:inserted_at)
  end

  identities do
    identity(:unique_rule, [:wallet, :verdict])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
