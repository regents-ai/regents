defmodule AshPlatform.Formation do
  use Ash.Domain,
    otp_app: :ash_platform

  resources do
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

      define :get_public_regent,
        action: :public_by_slug,
        args: [:slug],
        not_found_error?: false

      define :get_public_regent_profile, action: :public_profile, args: [:slug]

      define :update_profile, action: :update_profile, args: [:display_name, :summary]
    end
  end
end
