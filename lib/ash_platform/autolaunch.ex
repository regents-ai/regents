defmodule AshPlatform.Autolaunch do
  use Ash.Domain,
    otp_app: :ash_platform

  resources do
    resource AshPlatform.Autolaunch.LaunchDraft do
      define :create_launch_draft,
        action: :create_for_my_regent,
        args: [:title, :token_name, :symbol, :summary]

      define :list_my_launch_drafts, action: :mine
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
    end

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
  end
end
