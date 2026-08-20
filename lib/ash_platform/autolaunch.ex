defmodule AshPlatform.Autolaunch do
  use Ash.Domain,
    otp_app: :ash_platform

  require Ash.Query

  @payment_link_resource Module.concat(__MODULE__, "PaymentLink")
  @bid_operation Module.concat(__MODULE__, "BidOperation")
  @indexer_source Module.concat(__MODULE__, "Indexer.Source")
  @indexer_cursor Module.concat(__MODULE__, "Indexer.Cursor")
  @indexer_block Module.concat(__MODULE__, "Indexer.Block")
  @indexer_log Module.concat(__MODULE__, "Indexer.Log")

  resources do
    resource AshPlatform.Autolaunch.LaunchDraft do
      define :create_launch_draft,
        action: :create_for_my_regent,
        args: [:title, :token_name, :symbol, :summary]

      define :list_my_launch_drafts, action: :mine

      define :revise_launch_draft,
        action: :revise_by_owner,
        args: [:title, :token_name, :symbol, :summary]
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

  def prepare_subject_payment_link(
        subject_id,
        signer,
        label,
        canonical,
        opts \\ []
      ) do
    AshPlatform.Autolaunch.SubjectPaymentActions.prepare_payment_link(
      subject_id,
      signer,
      label,
      canonical,
      opts
    )
  end

  def prepare_subject_payment_link_canonical(
        subject_id,
        signer,
        receiver,
        canonical,
        opts \\ []
      ) do
    AshPlatform.Autolaunch.SubjectPaymentActions.prepare_payment_link_canonical(
      subject_id,
      signer,
      receiver,
      canonical,
      opts
    )
  end

  def prepare_subject_payment_link_state(
        subject_id,
        signer,
        receiver,
        active,
        replacement,
        opts \\ []
      ) do
    AshPlatform.Autolaunch.SubjectPaymentActions.prepare_payment_link_state(
      subject_id,
      signer,
      receiver,
      active,
      replacement,
      opts
    )
  end

  def prepare_subject_ingress_sweep(subject_id, signer, ingress_address, opts \\ []) do
    AshPlatform.Autolaunch.SubjectPaymentActions.prepare_ingress_sweep(
      subject_id,
      signer,
      ingress_address,
      opts
    )
  end

  def prepare_subject_stake(subject_id, signer, amount, opts) when is_list(opts) do
    prepare_subject_stake(subject_id, signer, amount, nil, opts)
  end

  def prepare_subject_stake(subject_id, signer, amount, receiver, opts) do
    AshPlatform.Autolaunch.SubjectPaymentActions.prepare_stake(
      subject_id,
      signer,
      amount,
      receiver,
      opts
    )
  end

  def prepare_subject_unstake(subject_id, signer, amount, opts \\ []) do
    AshPlatform.Autolaunch.SubjectPaymentActions.prepare_unstake(
      subject_id,
      signer,
      amount,
      opts
    )
  end

  def prepare_subject_claim_usdc(subject_id, signer, opts \\ []) do
    AshPlatform.Autolaunch.SubjectPaymentActions.prepare_claim_usdc(
      subject_id,
      signer,
      opts
    )
  end

  def confirm_subject_payment_action(
        envelope,
        transaction_hash,
        approval_transaction_hash,
        opts \\ []
      ) do
    AshPlatform.Autolaunch.SubjectPaymentActions.confirm(
      envelope,
      transaction_hash,
      approval_transaction_hash,
      opts
    )
  end

  def restore_submitted_subject_payment_action(envelope, opts \\ []) do
    AshPlatform.Autolaunch.SubjectPaymentActions.restore(envelope, opts)
  end

  def verify_subject_payment_approval(envelope, transaction_hash, opts \\ []) do
    AshPlatform.Autolaunch.SubjectPaymentActions.approval_status(
      envelope,
      transaction_hash,
      opts
    )
  end

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
