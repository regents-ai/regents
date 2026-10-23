defmodule Regents.AccessContext.AccountControl do
  @moduledoc """
  Ash-owned shell view model for the account target. `wallet` is the account's
  own wallet, lowercase, which the browser uses when one tab has several of the
  account's wallets connected.
  """

  @enforce_keys [:kind, :label, :profile_path]
  defstruct @enforce_keys ++ [avatar_src: nil, wallet: nil]
end
