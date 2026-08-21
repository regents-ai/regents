defmodule AshPlatform.Autolaunch do
  use Ash.Domain,
    otp_app: :ash_platform

  require Ash.Query

  @payment_link_resource Module.concat(__MODULE__, "PaymentLink")
  @bid_operation Module.concat(__MODULE__, "BidOperation")
  @subject_wallet_operation Module.concat(__MODULE__, "SubjectWalletOperation")
  @indexer_source Module.concat(__MODULE__, "Indexer.Source")
  @indexer_cursor Module.concat(__MODULE__, "Indexer.Cursor")
  @indexer_block Module.concat(__MODULE__, "Indexer.Block")
  @indexer_log Module.concat(__MODULE__, "Indexer.Log")

  resources do
    resource AshPlatform.Autolaunch.LaunchDraft do
      define :create_launch_draft, action: :create_for_my_regent
      define :list_my_launch_drafts, action: :mine
      define :revise_launch_draft, action: :revise_by_owner
    end

    resource AshPlatform.Autolaunch.Auction do
      define :list_auctions, action: :list_public
      define :list_recent_auctions, action: :recent_public
      define :list_featured_auctions, action: :featured_public

      define :get_public_auction,
        action: :public_by_id,
        args: [:id],
        not_found_error?: false

      define :import_auction,
        action: :import_public,
        args: [:title, :summary, :featured, :state, :opened_at]

      define :set_auction_bid_terms,
        action: :set_bid_terms,
        args: [
          :auction_address,
          :quote_token_address,
          :quote_token_symbol,
          :quote_token_decimals,
          :current_clearing_price
        ]

      define :bid_position, action: :bid_position, args: [:auction_id, :expected_signer]

      define :prepare_bid,
        action: :prepare_bid,
        args: [:auction_id, :expected_signer, :amount, :max_price]

      define :claim_bid_dispatch, action: :claim_bid_dispatch, args: [:action_id]
      define :bind_bid_hash, action: :bind_bid_hash, args: [:action_id, :step, :transaction_hash]
      define :verify_bid_step, action: :verify_bid_step, args: [:action_id]
      define :cancel_bid_review, action: :cancel_bid_review, args: [:action_id]
      define :close_bid_not_sent, action: :close_bid_not_sent, args: [:action_id]

      define :release_unstarted_bid_dispatch,
        action: :release_unstarted_bid_dispatch,
        args: [:action_id]

      define :start_new_bid, action: :start_new_bid, args: [:action_id]
      define :open_bid_operation, action: :open_bid_operation
    end

    # The durable bidder operation is written only by `BidActions` under a
    # session lease, so it is registered without a code interface of any kind.
    resource @bid_operation

    # The durable subject wallet operation is written only by
    # `SubjectWalletOperations` under a session lease, on the same terms.
    resource @subject_wallet_operation

    resource AshPlatform.Autolaunch.Token do
      define :list_tokens, action: :list_public
      define :list_top_tokens, action: :top_public
      define :list_recently_graduated_tokens, action: :recently_graduated_public

      define :get_public_token,
        action: :public_by_id,
        args: [:id],
        not_found_error?: false

      define :import_token,
        action: :import_public,
        args: [:auction_id, :name, :symbol, :summary, :graduated_at, :top_rank]

      define :import_subject_token,
        action: :import_public,
        args: [:auction_id, :subject_id, :name, :symbol, :summary, :graduated_at, :top_rank]

      define :list_subject_tokens,
        action: :for_subject,
        args: [:subject_id]

      define :get_latest_subject_token_price,
        action: :latest_price_for_subject,
        args: [:subject_id],
        not_found_error?: false

      define :set_subject_token_price,
        action: :set_price_snapshot,
        args: [:price_quote, :price_source, :price_updated_at]
    end

    resource AshPlatform.Autolaunch.Subject do
      define :list_subjects, action: :list_public

      define :get_public_subject,
        action: :public_by_id,
        args: [:subject_id],
        not_found_error?: false

      define :import_subject,
        action: :import_public,
        args: [
          :subject_id,
          :subject_kind,
          :chain_id,
          :token_address,
          :splitter_address,
          :ingress_address,
          :treasury_address,
          :factory_address,
          :creator_address,
          :staker_pool_bps,
          :protocol_skim_bps_snapshot,
          :current_protocol_skim_bps,
          :protocol_fee_usdc_total_raw,
          :regent_emission_total_raw,
          :pending_buyback_usdc_raw
        ]

      # Only 490.8.2/.3 projection and the deterministic browser fixture write
      # the canonical receiver, so it is a named SystemActor-only setter rather
      # than another positional import argument.
      define :set_subject_canonical_receiver,
        action: :set_canonical_receiver,
        args: [:canonical_receiver_address]
    end

    resource @payment_link_resource

    resource AshPlatform.Autolaunch.SubjectAction do
      define :list_subject_actions,
        action: :recent_for_subject,
        args: [:subject_identity]

      define :list_subject_settlements,
        action: :settlements_for_subject,
        args: [:subject_identity]

      define :import_subject_action,
        action: :import_public,
        args: [
          :subject_identity,
          :action,
          :owner_address,
          :chain_id,
          :tx_hash,
          :amount,
          :status,
          :block_number
        ]
    end

    resource AshPlatform.Autolaunch.LaunchJob do
      define :list_launches, action: :list_public

      define :get_public_launch,
        action: :public_by_id,
        args: [:job_id],
        not_found_error?: false

      define :import_launch,
        action: :import_public,
        args: [
          :job_id,
          :status,
          :step,
          :agent_id,
          :agent_name,
          :token_name,
          :token_symbol,
          :chain_id,
          :auction_id,
          :agent_safe_address,
          :auction_address,
          :token_address,
          :hook_address,
          :revenue_share_splitter_address,
          :started_at,
          :finished_at
        ]
    end

    resource AshPlatform.Autolaunch.Bid do
      define :list_my_bid_positions, action: :mine
      define :list_my_returnable_bid_positions, action: :returnable_mine
      define :list_my_claimed_token_positions, action: :claimed_mine
      define :get_my_bid_position, action: :owned_by_bid_id, args: [:bid_id]

      define :import_bid_position,
        action: :import_position,
        args: [
          :bid_id,
          :auction_id,
          :owner_address,
          :amount,
          :max_price,
          :current_clearing_price,
          :estimated_tokens_if_end_now,
          :status,
          :exited_at,
          :claimed_at
        ]

      define :set_bid_chain_identity,
        action: :set_chain_identity,
        args: [:auction_address, :onchain_bid_id]
    end

    # The Base log ledger is written only by its own SystemActor actions, so it
    # is registered without a code interface of any kind.
    resource @indexer_source
    resource @indexer_cursor
    resource @indexer_block
    resource @indexer_log
  end

  def quote_auction_bid(auction_id, amount, max_price, opts \\ []),
    do: AshPlatform.Autolaunch.BidActions.quote(auction_id, amount, max_price, opts)

  # The two bidder rules a presenter needs, owned here so the page and the named
  # preparation action can only ever answer the same way.
  defdelegate parse_bid_amount(value), to: AshPlatform.Autolaunch.BidActions, as: :atomic_amount
  defdelegate bid_amount_units(amount), to: AshPlatform.Autolaunch.BidActions, as: :units

  # The clean-V1 subject wallet lane. `SubjectWalletActions` proves the active
  # Privy wallet against the account the mounted lease locks before anything
  # private is read or anything durable moves, so these stay thin pass-throughs
  # and the resource itself keeps no code interface.
  defdelegate subject_wallet_state(subject_id, address, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :wallet_state

  defdelegate prepare_subject_wallet_action(subject_id, address, kind, params, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :prepare

  defdelegate claim_subject_wallet_dispatch(subject_id, action_id, address, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :claim_dispatch

  defdelegate bind_subject_wallet_hash(subject_id, action_id, step, hash, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :bind_hash

  defdelegate verify_subject_wallet_step(subject_id, action_id, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :verify

  defdelegate cancel_subject_wallet_review(subject_id, action_id, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :cancel

  defdelegate close_subject_wallet_not_sent(subject_id, action_id, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :close_not_sent

  defdelegate release_unstarted_subject_wallet_dispatch(subject_id, action_id, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :release_unstarted

  defdelegate start_new_subject_wallet_action(subject_id, action_id, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :start_new

  defdelegate open_subject_wallet_operation(subject_id, opts),
    to: AshPlatform.Autolaunch.SubjectWalletActions,
    as: :open_operation

  def list_public_auctions(mode, sort, limit, opts \\ []) do
    AshPlatform.Autolaunch.Auction
    |> Ash.Query.for_read(:read)
    |> filter_public_auctions(mode)
    |> sort_public_auctions(sort)
    |> Ash.Query.limit(limit)
    |> Ash.read(opts)
  end

  def list_public_tokens(limit, opts \\ []) do
    AshPlatform.Autolaunch.Token
    |> Ash.Query.for_read(:read)
    |> Ash.Query.sort(graduated_at: :desc, id: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.read(opts)
  end

  defp filter_public_auctions(query, mode) when mode in ["biddable", "live"],
    do: Ash.Query.filter(query, state: :active)

  defp filter_public_auctions(query, "failed_minimum"),
    do: Ash.Query.filter(query, state: :failed)

  defp filter_public_auctions(query, "graduated"),
    do: Ash.Query.filter(query, state: :graduated)

  defp filter_public_auctions(query, "all"), do: query

  defp sort_public_auctions(query, "oldest") do
    Ash.Query.sort(query, opened_at: :asc, inserted_at: :asc, id: :asc)
  end

  defp sort_public_auctions(query, "newest") do
    Ash.Query.sort(query, opened_at: :desc_nils_last, inserted_at: :desc, id: :asc)
  end
end
