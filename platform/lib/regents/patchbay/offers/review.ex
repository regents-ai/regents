defmodule Regents.Patchbay.Offers.Review do
  @moduledoc """
  Patchbay's decision on a campaign, by its id: approved, so its leases are
  shown and its purchases admitted, or pulled, so it is shown nowhere from
  that moment and never admitted again. Each decision is made at most once
  for a campaign and never changed or removed; pulled outweighs approved, so
  a pulled campaign stays pulled.

  Pulling stops the showing at once. The money of a lease already paid for
  follows the market's own path, which only the publisher's wallet can take:
  terminate the placement, then settle each of its slots, which refunds every
  live lease for the time it had left. Nothing here signs them.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Offers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @hash ~r/\A0x[0-9a-f]{64}\z/

  postgres do
    table("agent_offer_reviews")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:campaign_id, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: @hash]
    )

    attribute(:decision, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:approved, :pulled]]
    )

    attribute(:reason, :string,
      allow_nil?: false,
      default: "",
      constraints: [max_length: 500, allow_empty?: true]
    )

    attribute(:moderator_id, :uuid, allow_nil?: false)

    create_timestamp(:inserted_at, public?: true)
  end

  identities do
    identity(:once_each, [:campaign_id, :decision])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
