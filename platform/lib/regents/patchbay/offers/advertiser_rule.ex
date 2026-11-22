defmodule Regents.Patchbay.Offers.AdvertiserRule do
  @moduledoc """
  Patchbay's word on one advertiser wallet: `:accepted` or `:blocked`. A
  wallet Patchbay has not accepted is not admitted to buy, and a blocked
  wallet never is, even if it is also accepted.

  Only a moderator sets or removes a rule, on the operator page
  (`RegentsWeb.Patchbay.OffersAdminLive`), and reads them all; Patchbay reads them as
  the system when it admits a purchase or shows an offer.
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

  actions do
    defaults([:read, :destroy])

    # Setting a rule already there leaves it as it is.
    create :set do
      accept([:wallet, :verdict])
      upsert?(true)
      upsert_identity(:unique_rule)
      upsert_fields([])
      upsert_condition(expr(false))
      return_skipped_upsert?(true)
    end

    read :for_wallets do
      argument(:wallets, {:array, :string}, allow_nil?: false)
      filter(expr(wallet in ^arg(:wallets)))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :system))
      authorize_if(Regents.Patchbay.Checks.Moderator)
    end

    policy action_type([:create, :destroy]) do
      authorize_if(Regents.Patchbay.Checks.Moderator)
    end
  end
end
