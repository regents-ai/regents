defmodule Regents.Autolaunch do
  @moduledoc """
  Autolaunch's core, folded in from autolaunch.sh one slice at a time
  (`SOURCE.json` beside this module names what came from where). The pages
  brought so far (`RegentsWeb.Autolaunch`) read committed files and the fixed
  launch terms: the schedules (`LaunchActions`, `Stocks.LaunchActions`), on the
  launchpad version the deployment descriptions name for new launches, the
  time their blocks take (`LaunchChain`) and the Memestock fees
  (`Stocks.FeeSchedule`).

  It is also the Ash domain of Autolaunch's tables in the `autolaunch_app`
  schema, as autolaunch.sh's `Autolaunch` is: launches and their drafts,
  auctions, bids and their settlements, tokens with their trades, stakes and
  revenue, stocks and their launches, share videos and the X connection.
  Covered calls' two tables are their own domain,
  `Regents.Autolaunch.CoveredCalls`. Every attribute, relationship and identity
  is as autolaunch.sh has it. The reads behind the Auctions and Tokens lists
  (`Regents.Autolaunch.HomeMarket`) are here with their policies, with what
  their cards show of a record (`AuctionFigures`, `StoredImage` and
  `Token.presentation/1`), the dollar prices their figures are shown in
  (`UsdRates`) and the Auctions page's counts (`AuctionStats`); every other
  resource has no action yet and one policy refusing
  every action, so nothing here writes a row.

  It also reads the deployment descriptions, the files that say which
  contracts on which chain the site describes: Base's (`Lab`), Base Stocks'
  (`Stocks.Lab`) and Robinhood's (`Robinhood.Lab`), each named by a path
  setting and read once, as the site starts (`Regents.Autolaunch.Supervisor`
  calls `load_deployments!/0`).
  """
  use Boundary,
    top_level?: true,
    deps: [Regents, Regents.Chain, Regents.Stake],
    exports: [
      AuctionFigures,
      AuctionStats,
      HomeMarket,
      Lab,
      LaunchActions,
      LaunchChain,
      Robinhood.Lab,
      Search,
      Stocks.FeeSchedule,
      Stocks.LaunchActions,
      StoredImage,
      Supervisor,
      Token,
      UsdRates
    ]

  use Ash.Domain, otp_app: :regents

  alias Regents.Autolaunch.{Lab, Robinhood, Stocks}

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

    resource Regents.Autolaunch.Auction do
      define :list_path_peers, action: :path_peers, args: [:symbols]
    end

    resource Regents.Autolaunch.LaunchOperation
    resource Regents.Autolaunch.Stocks.LaunchDraft
    resource Regents.Autolaunch.Stocks.LaunchDraftImage
    resource Regents.Autolaunch.Stocks.LaunchOperation

    resource Regents.Autolaunch.Stocks.Stock do
      define :launch_currency_stocks, action: :launch_currencies, args: [:chain_id]
    end

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

  @doc """
  Reads each deployment description this site was given and keeps it
  (`Lab.loaded!/2`), as autolaunch.sh's `config/runtime.exs` loaded them at
  boot: Base's, Base Stocks' and Robinhood's. One that does not load raises its
  loader's error. A network whose setting is unset has no deployment, and
  nothing is read for it. `Regents.Autolaunch.Supervisor` calls it as it
  starts, so a malformed file stops the site's start as it stopped
  autolaunch.sh's, and every later read is answered from memory.
  """
  def load_deployments! do
    for {setting, loader} <- [
          autolaunch_base_deployment: Lab,
          autolaunch_base_stocks_deployment: Stocks.Lab,
          autolaunch_robinhood_deployment: Robinhood.Lab
        ],
        {:ok, path} <- [Application.fetch_env(:regents, setting)] do
      Lab.loaded!(loader, path)
    end

    :ok
  end
end
