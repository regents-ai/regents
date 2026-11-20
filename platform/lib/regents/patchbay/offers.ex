defmodule Regents.Patchbay.Offers do
  @moduledoc """
  Agent offers: businesses pay to reach the agents that read a site's page on
  Patchbay, and Patchbay, the publisher, earns USDC for showing them. Money,
  leases, refunds and payouts live in Patchbay's `AgentOfferMarket` on Base;
  these are the records kept off the chain: campaigns and their reviews, the
  advertisers accepted or blocked, pools of campaigns and the placements that
  show from them, the market's own events as the chain gave them, how far they
  have been read, and each offer shown.
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Patchbay.Offers.Campaign
    resource Regents.Patchbay.Offers.Review
    resource Regents.Patchbay.Offers.AdvertiserRule
    resource Regents.Patchbay.Offers.Pool
    resource Regents.Patchbay.Offers.PoolMember
    resource Regents.Patchbay.Offers.PlacementPool
    resource Regents.Patchbay.Offers.Placement
    resource Regents.Patchbay.Offers.Termination
    resource Regents.Patchbay.Offers.Lease
    resource Regents.Patchbay.Offers.Settlement
    resource Regents.Patchbay.Offers.Cursor
    resource Regents.Patchbay.Offers.Delivery
  end
end
