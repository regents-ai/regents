defmodule Regents.Account.Accounts do
  use Ash.Domain

  resources do
    resource Regents.Account.Accounts.HumanAccount do
      define :get_by_privy_did,
        action: :by_privy_did,
        args: [:privy_did],
        not_found_error?: false

      define :get_human_account, action: :read_self, args: [:id]
      define :points_account, action: :points_account, args: [:id]
      define :accounts_created_before, action: :created_before, args: [:at]
      define :accounts_by_privy_dids, action: :by_privy_dids, args: [:privy_dids]
      define :accounts_by_ids, action: :by_ids, args: [:ids]
      define :accounts_holding_wallets, action: :holding_wallets, args: [:wallets]

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
    end

    resource Regents.Account.Accounts.EnsIdentity do
      define :put_ens_identity,
        action: :put_resolved,
        args: [:human_account_id, :wallet_address, :ens_name, :ens_avatar_url]
    end

    resource Regents.Account.Accounts.SessionAuthority

    resource Regents.Account.Accounts.LinkedIdentity do
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

      # One statement finds the row still holding the subject for the account and
      # updates it; no row matched answers not found.
      define :refresh_linked_identity,
        action: :refresh_verified,
        get_by: [:provider, :subject, :human_account_id],
        default_options: [bulk_options: [strategy: :atomic]]

      define :list_my_linked_identities, action: :read_mine

      define :list_linked_identities_for_account,
        action: :for_account,
        args: [:human_account_id]

      define :get_first_link,
        action: :first_link,
        args: [:provider, :subject],
        not_found_error?: false

      define :linked_identities_before, action: :linked_before, args: [:provider, :at]
      define :remove_linked_identity, action: :remove_verified
    end
  end
end
