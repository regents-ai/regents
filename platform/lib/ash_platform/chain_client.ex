defmodule AshPlatform.ChainClient do
  @moduledoc """
  Reads at the latest Base block for a sent wallet step.

  `RegentChain.Outcome` reads sent steps through `transaction/2` and `receipt/2`.
  Every read is at `latest`: never count confirmations and never wait for `safe`
  or `finalized`. Regents reads Base through its own read endpoint
  (`:base_read_rpc_url`); the review's `rpc_url` is the public one the wallet is
  given, never a keyed server endpoint.
  """

  alias AshPlatform.WalletActions.Rpc

  @callback transaction(RegentChain.Review.chain(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback receipt(RegentChain.Review.chain(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}

  @rpc_opts [log_scope: "wallet steps"]

  @doc "The reader wallet steps use: this module, or the site's test stand-in."
  def module, do: Application.get_env(:ash_platform, :chain_client, __MODULE__)

  @doc "The transaction sent as `hash`, or `nil` while Base does not know it."
  def transaction(%{chain_id: 8453}, hash),
    do: Rpc.request("eth_getTransactionByHash", [hash], @rpc_opts)

  @doc "The receipt for `hash`, or `nil` while it has not landed."
  def receipt(%{chain_id: 8453}, hash),
    do: Rpc.request("eth_getTransactionReceipt", [hash], @rpc_opts)
end
