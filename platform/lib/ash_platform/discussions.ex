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
  end

  def comment_topic(target_type, target_id), do: "comments:#{target_type}:#{target_id}"

  def admin_actor?(actor), do: AshPlatform.Discussions.Comment.Checks.AdminWallet.admin?(actor)
end
