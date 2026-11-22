defmodule Regents.Autolaunch do
  @moduledoc """
  Autolaunch's core, folded in from autolaunch.sh one slice at a time
  (`SOURCE.json` beside this module names what came from where). The pages
  brought so far (`RegentsWeb.Autolaunch`) read only committed files.

  It is also the Ash domain of Autolaunch's tables in the `autolaunch_app`
  schema, as autolaunch.sh's `Autolaunch` is: launches and their drafts,
  auctions, bids and their settlements, tokens with their trades, stakes and
  revenue, stocks and their launches, share videos and the X connection.
  Covered calls' two tables are their own domain,
  `Regents.Autolaunch.CoveredCalls`. Every attribute, relationship and identity
  is as autolaunch.sh has it, with no action yet and one policy refusing every
  action, so nothing here reads or writes a row.
  """
  use Boundary, top_level?: true, deps: [Regents], exports: []

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Autolaunch.BidActivity
    resource Regents.Autolaunch.BidSettlement
    resource Regents.Autolaunch.TokenTrade
    resource Regents.Autolaunch.TokenRevenue
    resource Regents.Autolaunch.TokenStake
    resource Regents.Autolaunch.ShareVideoRequest
    resource Regents.Autolaunch.AuctionReading
    resource Regents.Autolaunch.AuctionPricePoint
    resource Regents.Autolaunch.LaunchDraft
    resource Regents.Autolaunch.LaunchDraftImage
    resource Regents.Autolaunch.Auction
    resource Regents.Autolaunch.LaunchOperation
    resource Regents.Autolaunch.Stocks.LaunchDraft
    resource Regents.Autolaunch.Stocks.LaunchDraftImage
    resource Regents.Autolaunch.Stocks.LaunchOperation
    resource Regents.Autolaunch.Stocks.Stock
    resource Regents.Autolaunch.Stocks.AdmissionScan
    resource Regents.Autolaunch.Stocks.StockCandidate
    resource Regents.Autolaunch.Token
    resource Regents.Autolaunch.Subject
    resource Regents.Autolaunch.PaymentLink
    resource Regents.Autolaunch.LaunchJob
    resource Regents.Autolaunch.Bid
    resource Regents.Autolaunch.TreasurySecurityReport
    resource Regents.Autolaunch.Robinhood.LaunchReview
    resource Regents.Autolaunch.LaunchDiscovery
    resource Regents.Autolaunch.AuctionFinish
    resource Regents.Autolaunch.AuctionFinish.Transaction
    resource Regents.Autolaunch.XConnection
  end

  @doc "`:ok`: nothing Autolaunch serves yet reads anything that could be unavailable."
  def health, do: :ok
end
