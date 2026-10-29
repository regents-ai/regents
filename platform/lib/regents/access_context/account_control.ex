defmodule Regents.AccessContext.AccountControl do
  @moduledoc """
  Ash-owned shell view model for the account target. `wallet` is the account's
  own wallet, lowercase, which the browser uses when one tab has several of the
  account's wallets connected; `ens_name` is the ENS name that points to it,
  which the account menu and the Account page show for the wallet.
  """

  @enforce_keys [:kind, :label, :profile_path]
  defstruct @enforce_keys ++ [avatar_src: nil, wallet: nil, ens_name: nil]
end
