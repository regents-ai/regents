defmodule Regents.Autolaunch do
  @moduledoc """
  Autolaunch's core domain, folded in from autolaunch.sh (`SOURCE.json` beside
  this module names what came from where).

  Owns Autolaunch's tables in the `autolaunch_app` schema on `Regents.Repo`:
  launches and their drafts, auctions, bids and their settlements, tokens with
  their trades, stakes and revenue, stocks and their launches, share videos,
  and X connections. Covered calls, Exposure, and Earn are sibling domains
  under `Regents.Autolaunch.*`.
  """
  use Boundary,
    top_level?: true,
    deps: [Regents, Regents.Chain, Regents.Stake],
    exports: [
      AgentBid,
      AgentBid.Refused,
      AgentDrafts,
      AgentFinish,
      AgentFinish.Refused,
      AgentLaunch,
      AgentLaunch.Refused,
      AgentRobinhoodBid,
      AgentRobinhoodBid.Refused,
      AgentStake,
      AgentStake.Refused,
      Auction,
      AuctionActivity,
      AuctionBook,
      AuctionFigures,
      AuctionFinish,
      AuctionMarket,
      AuctionPricePoint,
      AuctionReading,
      AuctionSnapshot,
      AuctionStage,
      AuctionStats,
      AuctionTerms,
      Bid,
      BidActions,
      BidActivity,
      BidIdentity,
      BidPrice,
      BidReceipt,
      BidSettlement,
      BidSettlementActions,
      BidSlippage,
      Chain.Abi,
      Chain.Calls,
      Chain.CcaLists,
      Chain.CcaSettlement,
      Chain.Client,
      Chain.LaunchAbi,
      Chain.Lifecycle,
      Chain.Multicall,
      Chain.Permit2Abi,
      Chain.Rpc,
      Chain.SubjectAbi,
      ChainHead,
      ChainWatch,
      CoveredCalls,
      CoveredCalls.Answer,
      CoveredCalls.Book,
      CoveredCalls.Chain,
      CoveredCalls.Deployment,
      CoveredCalls.Market,
      CoveredCalls.Positions,
      CoveredCalls.PriceLine,
      CoveredCalls.Quote,
      CoveredCalls.Refused,
      CoveredCalls.Sales,
      CoveredCalls.Steps,
      CoveredCalls.Terms,
      DexScreener,
      Earn,
      Earn.Amount,
      Earn.Answer,
      Earn.Catalog,
      Earn.Chain,
      Earn.Product,
      Earn.Refused,
      Earn.SharedTerms,
      Earn.States,
      Earn.Steps,
      Exposure,
      Exposure.Chain,
      Exposure.Deployment,
      Exposure.Ledger,
      Exposure.Series,
      Exposure.Steps,
      FinishActions,
      HomeMarket,
      ImageColor,
      Lab,
      LabAbi,
      LabPositions,
      LabProjection,
      LabRpc,
      LabRpcUrl,
      LaunchActions,
      LaunchChain,
      LaunchDiscovery,
      LaunchDiscovery.Count,
      LaunchDraft,
      LaunchDraft.ImageValidator,
      LaunchDraftImage,
      LaunchDraftImageStorage,
      LaunchIdentity,
      LaunchJob,
      LaunchLinks,
      LaunchOperation,
      LaunchReviews,
      LaunchedDrafts,
      Listings,
      MarketTicker,
      MemestockLanes,
      PaymentLink,
      Pool,
      PoolFees,
      PoolPrice,
      PoolRange,
      Prelaunch,
      PriceFeedHistory,
      PriceHistory,
      PublicIdentity,
      ReadFailedError,
      ReadFailure,
      RegentFacts,
      Robinhood.BlockClock,
      Robinhood.Discovery,
      Robinhood.Lab,
      Robinhood.LabAbi,
      Robinhood.LaunchReview,
      Robinhood.Launchpad,
      Robinhood.Pool,
      Robinhood.Positions,
      Robinhood.StockBidActions,
      Robinhood.StockBidSettlementActions,
      Robinhood.StocksLaunchActions,
      Search,
      ShareVideoRequest,
      Stocks.AdmissionScan,
      Stocks.Amounts,
      Stocks.Assets,
      Stocks.Faucet,
      Stocks.FeeSchedule,
      Stocks.Lab,
      Stocks.LabAbi,
      Stocks.LaunchActions,
      Stocks.LaunchDraft,
      Stocks.LaunchDraftImage,
      Stocks.LaunchDraftImageStorage,
      Stocks.LaunchOperation,
      Stocks.MarketData,
      Stocks.StakeActions,
      Stocks.Stock,
      Stocks.StockCandidate,
      Stocks.UpcomingCatalog,
      StoredImage,
      Subject,
      SubjectWalletActions,
      Supervisor,
      SwapActions,
      Ticker,
      Token,
      TokenHoldings,
      TokenPage,
      TokenRevenue,
      TokenStake,
      TokenTrade,
      TokenTrades,
      TreasurySecurity,
      TreasurySecurityReport,
      UnavailableError,
      UsdRates,
      WalletHistory,
      XConnection,
      XOAuth
    ]

  use Ash.Domain, otp_app: :regents

  alias Regents.Autolaunch.{Lab, Robinhood, Stocks}

  @payment_link_resource Module.concat(__MODULE__, "PaymentLink")
  @launch_draft_image_resource Module.concat(__MODULE__, "LaunchDraftImage")
  @launch_operation Module.concat(__MODULE__, "LaunchOperation")

  resources do
    resource Regents.Autolaunch.BidActivity do
      define :auction_bids, action: :for_auction, args: [:auction_id]
      define :auction_bid, action: :for_bid, args: [:auction_id, :bid_id], not_found_error?: false
      define :recent_bid_activity, action: :recent
    end

    resource Regents.Autolaunch.BidSettlement do
      define :bid_settlements, action: :for_bid, args: [:auction_id, :bid_id]
    end

    resource Regents.Autolaunch.TokenTrade do
      define :token_trades, action: :for_token, args: [:token_id]

      define :get_token_trade,
        action: :by_pool_log,
        args: [:token_id, :transaction_hash, :log_index],
        not_found_error?: false

      define :recent_token_trades, action: :recent
    end

    resource Regents.Autolaunch.TokenRevenue do
      define :token_revenue, action: :for_token, args: [:token_id]
    end

    resource Regents.Autolaunch.TokenStake do
      define :get_token_stake, action: :by_id, args: [:id], not_found_error?: false
    end

    resource Regents.Autolaunch.ShareVideoRequest do
      define :request_share_video, action: :request
      define :latest_share_video_request, action: :latest, args: [:key], not_found_error?: false

      define :own_share_video_requests,
        action: :own,
        args: [:human_account_id, :auction_id, :kind, :wallet]

      define :own_market_share_video_requests,
        action: :own_market,
        args: [:human_account_id, :subject, :kind, :wallet]

      define :share_video_mp4, action: :video, args: [:id]
      define :share_video_room, action: :room, args: [:bytes]
      define :hand_over_share_video, action: :hand_over
    end

    resource Regents.Autolaunch.AuctionReading do
      define :get_auction_reading, action: :read, get_by: [:auction_id], not_found_error?: false
      define :record_auction_reading, action: :record
      define :refresh_auction_reading, action: :refresh
      define :degrade_auction_reading, action: :degrade
    end

    resource Regents.Autolaunch.AuctionPricePoint do
      define :auction_price_points, action: :for_auction, args: [:auction_id]

      define :latest_price_point_before,
        action: :latest_before,
        args: [:auction_id, :block_number],
        not_found_error?: false
    end

    resource Regents.Autolaunch.LaunchDraft do
      define :create_launch_draft, action: :create_for_owner
      define :list_my_launch_drafts, action: :mine

      define :get_my_account_launch_draft,
        action: :mine_account_owned,
        not_found_error?: false

      define :get_my_launch_draft,
        action: :mine_by_id,
        args: [:id],
        not_found_error?: false

      define :get_my_launch_draft_for_update,
        action: :mine_by_id_for_update,
        args: [:id],
        not_found_error?: false

      define :autosave_launch_token_details, action: :autosave_token_details
      define :autosave_launch_treasury, action: :autosave_treasury

      define :confirm_launch_agent_treasury,
        action: :confirm_agent_treasury,
        args: [:treasury]

      define :attach_launch_draft_image,
        action: :attach_image,
        args: [:launch_draft_image_id]

      define :launch_draft_naming_listed_launch,
        action: :naming_listed_launch,
        args: [:human_account_id, :name, :symbol],
        functions: [:subject]

      define :clear_launch_draft,
        action: :clear,
        default_options: [bulk_options: [strategy: :atomic, return_errors?: true]]
    end

    resource @launch_draft_image_resource do
      define :create_launch_draft_image,
        action: :store_for_owner,
        args: [:bytes, :content_type, :original_filename, :launch_draft_id]

      define :get_my_launch_draft_image_for_reuse,
        action: :mine_for_reuse,
        args: [:launch_draft_id, :digest],
        not_found_error?: false

      define :get_my_launch_draft_image_by_id,
        action: :mine_by_id,
        args: [:launch_draft_id, :id],
        not_found_error?: false

      define :get_public_launch_draft_image,
        action: :public_by_id_and_digest,
        args: [:id, :digest],
        not_found_error?: false

      define :launch_draft_image_colors, action: :public_colors, args: [:ids]
    end

    resource Regents.Autolaunch.Auction do
      define :auction_counts, action: :counts
      define :list_my_auctions, action: :by_creator
      define :sitemap_auctions, action: :sitemap

      define :get_public_auction,
        action: :public_by_id,
        args: [:id],
        not_found_error?: false

      define :get_listed_auction,
        action: :listed_by_id,
        args: [:id],
        not_found_error?: false

      define :get_robinhood_auction,
        action: :robinhood_by_address,
        args: [:auction_address],
        not_found_error?: false

      define :get_held_robinhood_auction,
        action: :robinhood_held_by_address,
        args: [:auction_address],
        not_found_error?: false

      define :list_auctions_by_path, action: :by_path, args: [:symbol, :tail]
      define :list_path_peers, action: :path_peers, args: [:symbols]
      define :record_launch_auction, action: :record_launch

      define :set_auction_bid_terms,
        action: :set_bid_terms,
        args: [
          :auction_address,
          :quote_token_address,
          :quote_token_symbol,
          :quote_token_decimals,
          :current_clearing_price
        ]

      define :set_auction_treasury_security_report,
        action: :set_treasury_security_report,
        args: [:treasury_security_report_id]

      define :get_auction_by_chain_address,
        action: :by_chain_address,
        args: [:chain_id, :auction_address],
        not_found_error?: false

      define :get_lab_market_auction_for_update,
        action: :lab_by_id_for_update,
        args: [:id],
        not_found_error?: false

      define :refresh_lab_market_auction,
        action: :refresh_lab_market,
        args: [:state, :current_clearing_price]

      define :bid_position, action: :bid_position, args: [:auction_id, :expected_signer]
      define :hide_auction, action: :hide
      define :show_auction, action: :show
    end

    resource @launch_operation do
      define :get_launch_review_by_action_id,
        action: :by_action_id,
        args: [:action_id],
        not_found_error?: false

      define :list_launch_reviews_for_signer,
        action: :for_signer_on_chain,
        args: [:signer, :chain_id]

      define :lock_launch_review,
        action: :by_id_for_update,
        args: [:id],
        not_found_error?: false

      define :verify_launch_review, action: :verify
    end

    resource Regents.Autolaunch.Stocks.LaunchDraft do
      define :create_stocks_launch_draft, action: :create_for_owner

      define :get_my_stocks_launch_draft,
        action: :mine_account_owned,
        not_found_error?: false

      define :get_my_stocks_launch_draft_by_id,
        action: :mine_by_id,
        args: [:id],
        not_found_error?: false

      define :get_my_stocks_launch_draft_for_update,
        action: :mine_by_id_for_update,
        args: [:id],
        not_found_error?: false

      define :autosave_stocks_token_details, action: :autosave_token_details
      define :choose_stocks_launch_chain, action: :choose_chain, args: [:chain]
      define :autosave_stocks_terms, action: :autosave_terms

      define :attach_stocks_launch_draft_image,
        action: :attach_image,
        args: [:stock_launch_draft_image_id]

      define :stocks_launch_draft_naming_listed_launch,
        action: :naming_listed_launch,
        args: [:human_account_id, :name, :symbol],
        functions: [:subject]

      define :clear_stocks_launch_draft,
        action: :clear,
        default_options: [bulk_options: [strategy: :atomic, return_errors?: true]]
    end

    resource Regents.Autolaunch.Stocks.LaunchDraftImage do
      define :create_stock_launch_draft_image,
        action: :store_for_owner,
        args: [:bytes, :content_type, :original_filename, :stock_launch_draft_id]

      define :get_my_stock_launch_draft_image,
        action: :mine,
        args: [:stock_launch_draft_id],
        not_found_error?: false

      define :get_my_stock_launch_draft_image_for_reuse,
        action: :mine_for_reuse,
        args: [:stock_launch_draft_id, :digest],
        not_found_error?: false

      define :get_my_stock_launch_draft_image_by_id,
        action: :mine_by_id,
        args: [:stock_launch_draft_id, :id],
        not_found_error?: false

      define :get_public_stock_launch_draft_image,
        action: :public_by_id_and_digest,
        args: [:id, :digest],
        not_found_error?: false

      define :stock_launch_draft_image_colors, action: :public_colors, args: [:ids]
    end

    resource Regents.Autolaunch.Stocks.LaunchOperation do
      define :get_stocks_launch_review_by_action_id,
        action: :by_action_id,
        args: [:action_id],
        not_found_error?: false

      define :list_stocks_launch_reviews_for_signer,
        action: :for_signer_on_chain,
        args: [:signer, :chain_id]

      define :lock_stocks_launch_review,
        action: :by_id_for_update,
        args: [:id],
        not_found_error?: false

      define :verify_stocks_launch_review, action: :verify
    end

    resource Regents.Autolaunch.Stocks.Stock do
      define :chain_stocks, action: :on_chain, args: [:chain_id]
      define :launch_currency_stocks, action: :launch_currencies, args: [:chain_id]
      define :record_stock_admission, action: :record_admission
      define :withdraw_stock_admission, action: :withdraw_admission
    end

    resource Regents.Autolaunch.Stocks.AdmissionScan do
      define :stock_admission_scan,
        action: :of_launchpad,
        args: [:chain_id, :launchpad, :run_id],
        not_found_error?: false

      define :advance_stock_admission_scan, action: :advance
    end

    resource Regents.Autolaunch.Stocks.StockCandidate do
      define :chain_stock_candidates, action: :on_chain, args: [:chain_id]
      define :eligible_stock_candidates, action: :eligible
      define :list_stock_candidate, action: :list
      define :unlist_stock_candidate, action: :unlist
      define :mark_stock_candidate_tried, action: :mark_tried
    end

    resource Regents.Autolaunch.Token do
      define :list_tokens, action: :list_public
      define :list_listed_tokens, action: :listed
      define :sitemap_tokens, action: :sitemap
      define :list_top_tokens, action: :top_public
      define :list_recently_graduated_tokens, action: :recently_graduated_public

      define :get_public_token,
        action: :public_by_id,
        args: [:id],
        not_found_error?: false

      define :get_listed_token,
        action: :listed_by_id,
        args: [:id],
        not_found_error?: false

      define :get_robinhood_token,
        action: :robinhood_by_address,
        args: [:token_address],
        not_found_error?: false

      define :get_public_token_by_auction,
        action: :public_by_auction,
        args: [:auction_id],
        not_found_error?: false

      define :project_lab_token, action: :project_lab

      define :get_token_for_projection,
        action: :projection_by_auction,
        args: [:auction_id],
        not_found_error?: false

      define :get_latest_subject_token_price,
        action: :latest_price_for_subject,
        args: [:subject_id],
        not_found_error?: false

      define :set_subject_token_price,
        action: :set_price_snapshot,
        args: [:price_quote, :price_source, :price_updated_at]
    end

    resource Regents.Autolaunch.Subject do
      define :get_public_subject,
        action: :public_by_id,
        args: [:subject_id],
        not_found_error?: false

      define :project_lab_subject, action: :project_lab
    end

    resource @payment_link_resource

    resource Regents.Autolaunch.LaunchJob do
      define :project_lab_launch, action: :project_lab
    end

    resource Regents.Autolaunch.Bid do
      define :list_wallet_bid_positions, action: :mine_by_wallets, args: [:wallet_addresses]
      define :list_wallet_bids_to_settle, action: :to_settle_by_wallets, args: [:wallet_addresses]
      define :get_my_bid_position, action: :owned_by_bid_id, args: [:bid_id]

      define :get_agent_bid_position,
        action: :agent_by_bid_id,
        args: [:bid_id],
        not_found_error?: false

      define :get_bid_position, action: :by_id, args: [:id], not_found_error?: false
    end

    resource Regents.Autolaunch.TreasurySecurityReport do
      define :list_treasury_security_reports, action: :for_address, args: [:address]

      define :get_treasury_security_report,
        action: :by_id,
        args: [:id],
        not_found_error?: false
    end

    resource Regents.Autolaunch.AgentBid do
      define :prepare_bid, action: :prepare
      define :prepare_bid_settlement, action: :settle
    end

    resource Regents.Autolaunch.AgentRobinhoodBid do
      define :prepare_robinhood_bid, action: :prepare
      define :prepare_robinhood_bid_settlement, action: :settle
    end

    resource Regents.Autolaunch.AgentLaunch do
      define :prepare_launch, action: :prepare
    end

    resource Regents.Autolaunch.AgentFinish do
      define :prepare_finish, action: :prepare
    end

    resource Regents.Autolaunch.AgentStake do
      define :prepare_stake, action: :prepare
    end

    resource Regents.Autolaunch.Robinhood.LaunchReview do
      define :record_robinhood_launch_review, action: :record

      define :matching_robinhood_launch_review,
        action: :matching,
        args: [:chain_id, :signer, :name, :symbol, :stock],
        not_found_error?: false

      define :adopt_robinhood_launch_review, action: :adopt
    end

    resource Regents.Autolaunch.LaunchDiscovery do
      define :record_launch_discovery, action: :record
      define :recorded_launch_discoveries, action: :recorded, args: [:chain_id, :contract]
    end

    resource Regents.Autolaunch.AuctionFinish do
      define :record_auction_finish, action: :record
      define :recorded_auction_finishes, action: :recorded, args: [:chain_id, :contract]
    end

    resource Regents.Autolaunch.AuctionFinish.Transaction do
      define :record_auction_finish_transaction, action: :record

      define :unsettled_auction_finish_transaction,
        action: :unsettled,
        args: [:auction_finish_id],
        not_found_error?: false

      define :highest_auction_finish_nonce,
        action: :highest_nonce,
        args: [:chain_id, :signer],
        not_found_error?: false

      define :settle_auction_finish_transaction, action: :settle, args: [:outcome]
    end

    resource Regents.Autolaunch.XConnection do
      define :begin_x_connection_attempt, action: :begin_attempt
      define :record_x_connection_intent, action: :record_intent
      define :list_my_x_connections, action: :mine

      define :get_my_x_connection,
        action: :mine_by_role,
        args: [:role],
        not_found_error?: false

      define :get_my_x_connection_for_update,
        action: :mine_by_role_for_update,
        args: [:role],
        not_found_error?: false

      define :list_public_x_connections,
        action: :public_for_humans,
        args: [:human_account_ids]

      define :get_connected_x_profile,
        action: :connected_profile,
        args: [:x_user_id],
        not_found_error?: false

      define :x_profiles_connected_before, action: :profiles_connected_before, args: [:at]
      define :replace_x_connection_attempt, action: :replace_attempt
      define :complete_x_connection_attempt, action: :complete_attempt
      define :clear_x_connection_attempt, action: :clear_attempt

      define :cancel_x_connection_attempt,
        action: :cancel_attempt,
        args: [:intent_sequence, :intent_generation]

      define :disconnect_x_connection,
        action: :disconnect,
        args: [:intent_sequence, :intent_generation]
    end
  end

  @doc "`:ok`: Autolaunch runtime health."
  def health, do: :ok

  @doc "Observes Base and persists one immutable treasury security report."
  def observe_treasury_security(address, evidence, opts \\ []) do
    Regents.Autolaunch.TreasurySecurity.observe(address, evidence, Keyword.get(opts, :actor))
  end

  @doc "Returns the newest stored observation without triggering provider work."
  def current_treasury_security(address, opts \\ []) do
    with {:ok, address} <- RegentChain.Address.normalize(address),
         {:ok, reports} <- list_treasury_security_reports(address, opts) do
      {:ok, List.first(reports)}
    end
  end

  def quote_auction_bid(auction_id, amount, max_price, opts \\ []),
    do: Regents.Autolaunch.BidActions.quote(auction_id, amount, max_price, opts)

  @doc "The site's public origin (`https://regents.sh` in prod, `http://localhost:4000` locally)."
  def site_url, do: Application.get_env(:regents, :site_origin, "http://localhost:4000")

  @doc """
  Reads each deployment description this site was given and keeps it
  (`Lab.loaded!/2`): Base's, Base Stocks', Robinhood's, Covered Calls' and Exposure's.
  """
  def load_deployments! do
    for {setting, loader} <- [
          autolaunch_base_deployment: Lab,
          autolaunch_base_stocks_deployment: Stocks.Lab,
          autolaunch_robinhood_deployment: Robinhood.Lab,
          autolaunch_base_covered_calls_deployment: Regents.Autolaunch.CoveredCalls.Deployment,
          autolaunch_base_exposure_deployment: Regents.Autolaunch.Exposure.Deployment
        ],
        {:ok, path} <- [Application.fetch_env(:regents, setting)] do
      Lab.loaded!(loader, path)
    end

    :ok
  end
end
