defmodule Regents.AccessContext.AccountControl do
  @moduledoc """
  Ash-owned shell view model for the account target. `wallet` is the account's
  main wallet, lowercase, which the browser makes the active wallet whenever the
  tab has it connected; `ens_name` is the ENS name that points to it,
  which the account menu and the Account page show for the wallet.
  """

  @enforce_keys [:kind, :label, :profile_path]
  defstruct @enforce_keys ++ [avatar_src: nil, wallet: nil, ens_name: nil]
end
