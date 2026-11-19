defmodule Regents.Chain do
  @moduledoc """
  Chain reading and wallet-step plumbing that Stake and Redeem share.
  """
  use Boundary, top_level?: true, exports: [Abi, Address, Client, Refresh, Rpc]
end
