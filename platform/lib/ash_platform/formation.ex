defmodule AshPlatform.Formation do
  use Ash.Domain,
    otp_app: :ash_platform

  resources do
    resource AshPlatform.Formation.AgentLink do
      define :claim_agent_link, action: :claim, args: [:regent_id, :code, :identity]
      define :list_my_agent_links, action: :mine_for_regent, args: [:regent_id]
      define :revoke_agent_link, action: :revoke
    end

    resource AshPlatform.Formation.AgentPairingCode do
      define :issue_agent_pairing_code, action: :issue, args: [:regent_id]
    end

    resource AshPlatform.Formation.CloudRuntime do
      define :provision_cloud_runtime, action: :provision_for_my_regent
      define :get_my_cloud_runtime, action: :mine

      define :get_public_cloud_profile_source,
        action: :public_profile_source,
        args: [:regent_id],
        not_found_error?: false

      define :refresh_cloud_runtime, action: :refresh_status
    end

    resource AshPlatform.Formation.Regent do
      define :form_regent, action: :form_regent, args: [:slug, :display_name]
      define :get_my_regent, action: :my_regent, not_found_error?: false

      define :get_public_regent_by_id,
        action: :public_by_id,
        args: [:id],
        not_found_error?: false

      define :get_public_regent,
        action: :public_by_slug,
        args: [:slug],
        not_found_error?: false

      define :get_public_regent_profile, action: :public_profile, args: [:slug]

      define :update_profile, action: :update_profile, args: [:display_name, :summary]
    end
  end
end
