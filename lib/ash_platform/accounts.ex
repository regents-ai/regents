defmodule AshPlatform.Accounts do
  use Ash.Domain

  resources do
    resource AshPlatform.Accounts.HumanAccount do
      define :get_by_privy_did,
        action: :by_privy_did,
        args: [:privy_did],
        not_found_error?: false

      define :get_human_account, action: :read_self, args: [:id]

      define :register_verified,
        action: :register_verified,
        args: [:privy_did, :wallet_address, :wallet_addresses]

      define :refresh_verified,
        action: :refresh_verified,
        args: [:wallet_address, :wallet_addresses]

      define :set_display_name, action: :set_display_name
    end
  end
end
