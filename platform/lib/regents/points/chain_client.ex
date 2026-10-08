defmodule Regents.Points.ChainClient do
  @moduledoc """
  Regent Points' reads on Base: blocks, NFT balances at a block and transfer
  logs, through this site's own Base read endpoint (`:base_read_rpc_url`).
  """

  @behaviour RegentPoints.ChainClient

  alias Regents.WalletActions.Rpc

  @impl true
  def rpc(%{chain_id: 8453}, method, params),
    do: Rpc.request(method, params, log_scope: "points")
end
