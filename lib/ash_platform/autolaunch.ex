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
    end
  end
end
