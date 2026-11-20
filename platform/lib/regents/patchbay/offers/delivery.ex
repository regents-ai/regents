defmodule Regents.Patchbay.Offers.Delivery do
  @moduledoc """
  One paid offer Patchbay put in front of a reader: which lease, which
  campaign, on what (`context`, the page or answer it went with), through
  which door (`surface`), to whom, and on which day. Each is written once and
  never changed.

  A reader is a signed agent (`:agent`, its profile), a signed-in person
  (`:person`, their profile) or anyone else (`:visitor`, the keyed hash of
  their address). The same lease
  shown to the same reader with the same page on the same day is one
  delivery, so a page read again, refreshed or retried is not a second one.
  Deliveries are how a campaign's daily limit is kept.

  A delivery is Patchbay's own record that it served the offer, not proof the
  reader paid it any attention. Its id is what a signed receipt would name.

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
    table("agent_offer_deliveries")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:lease, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:campaign_id, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: @hash]
    )

    attribute(:surface, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:page, :markdown, :json, :mcp]]
    )

    attribute(:viewer_kind, :atom,
      allow_nil?: false,
      constraints: [one_of: [:agent, :person, :visitor]]
    )

    attribute(:viewer, :string, allow_nil?: false, constraints: [max_length: 100])
    attribute(:context, :string, allow_nil?: false, public?: true, constraints: [max_length: 300])
    attribute(:delivered_on, :date, allow_nil?: false, public?: true)

    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    belongs_to :lease, Regents.Patchbay.Offers.Lease do
      allow_nil?(false)
      public?(true)
    end

    has_one :campaign, Regents.Patchbay.Offers.Campaign do
      source_attribute(:campaign_id)
      destination_attribute(:campaign_id)
    end
  end

  identities do
    identity(:once_a_day, [:lease_id, :viewer_kind, :viewer, :context, :delivered_on])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
