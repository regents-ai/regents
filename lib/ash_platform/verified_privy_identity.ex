defmodule AshPlatform.VerifiedPrivyIdentity do
  @moduledoc false

  @enforce_keys [:privy_user_id, :session_id, :wallet_addresses]
  defstruct [:privy_user_id, :session_id, :wallet_address, :wallet_addresses]

  @type t :: %__MODULE__{
          privy_user_id: String.t(),
          session_id: String.t(),
          wallet_address: String.t() | nil,
          wallet_addresses: [String.t()]
        }
end
