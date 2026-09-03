defmodule AshPlatform.Accounts do
  use Ash.Domain

  resources do
    resource AshPlatform.Accounts.HumanAccount do
      define :get_by_privy_did,
        action: :by_privy_did,
        args: [:privy_did],
        not_found_error?: false

      define :get_human_account, action: :read_self, args: [:id]

      define :get_public_profile_source,
        action: :public_profile_source,
        args: [:id],
        not_found_error?: false

      define :register_verified,
        action: :register_verified,
        args: [:privy_did, :wallet_address, :wallet_addresses]

      define :refresh_verified,
        action: :refresh_verified,
        args: [:wallet_address, :wallet_addresses]

      define :set_display_name, action: :set_display_name
      define :set_avatar, action: :set_avatar
    end

    resource AshPlatform.Accounts.EnsIdentity do
      define :put_ens_identity,
        action: :put_resolved,
        args: [:human_account_id, :ens_name, :ens_avatar_url]
    end

    resource AshPlatform.Accounts.SessionAuthority

    resource AshPlatform.Accounts.LinkedIdentity do
      define :upsert_linked_identity,
        action: :upsert_verified,
        args: [
          :provider,
          :subject,
          :username,
          :display_name,
          :verified_at,
          :metadata,
          :human_account_id
        ]

      define :list_my_linked_identities, action: :read_mine

      define :list_linked_identities_for_account,
        action: :for_account,
        args: [:human_account_id]

      define :get_linked_identity_by_subject,
        action: :by_provider_subject,
        args: [:provider, :subject],
        not_found_error?: false

      define :remove_linked_identity, action: :remove_verified
    end
  end
end
