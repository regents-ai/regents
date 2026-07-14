defmodule AshPlatform.Discussions do
  use Ash.Domain,
    otp_app: :ash_platform

  resources do
    resource AshPlatform.Discussions.Comment do
      define :post_comment,
        action: :post,
        args: [:target_type, :target_id, :body, :client_request_id]

      define :list_comments, action: :list_for_target, args: [:target_type, :target_id]
      define :delete_comment, action: :delete

      define :get_comment_audit,
        action: :audit_by_id,
        args: [:id],
        not_found_error?: false
    end

    resource AshPlatform.Discussions.CommentReaction do
      define :set_comment_reaction,
        action: :set,
        args: [:comment_id, :value]

      define :list_comment_reactions,
        action: :list_for_comments,
        args: [:comment_ids]

      define :get_my_comment_reaction,
        action: :mine_for_comment,
        args: [:comment_id],
        not_found_error?: false

      define :remove_comment_reaction, action: :remove
    end
  end

  def comment_topic(target_type, target_id), do: "comments:#{target_type}:#{target_id}"

  def admin_actor?(actor), do: AshPlatform.Discussions.Comment.Checks.AdminWallet.admin?(actor)
end
