defmodule AshPlatform.Formation do
  use Ash.Domain,
    otp_app: :ash_platform

  resources do
    resource AshPlatform.Formation.Regent do
      define :form_regent, action: :form_regent, args: [:slug, :display_name]
      define :get_my_regent, action: :my_regent, not_found_error?: false

      define :get_public_regent,
        action: :public_by_slug,
        args: [:slug],
        not_found_error?: false
    end
  end
end
