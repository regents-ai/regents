defmodule Regents.ChainClient do
  @moduledoc """
  Reads at the latest block for a sent wallet step on Base.

  `RegentChain.Outcome` reads sent steps through `transaction/2` and `receipt/2`.
  Every read is at `latest`: never wait for `safe` or `finalized`. Regents reads
  Base through its own read endpoint (`:base_read_rpc_url`), never the review's
  public `rpc_url`, which no wallet is given either: Privy moves a wallet to Base
  from its own list of networks.
  """

  alias Regents.WalletActions.Rpc

  @callback transaction(RegentChain.Review.chain(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback receipt(RegentChain.Review.chain(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}

  @rpc_opts [scope: "wallet_steps"]
  @base %{chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"}

  @doc """
  Base, the one chain every wallet step goes to. The root layout names it to
  Privy (the `wallet-chain-id` meta), which connects wallets on it and switches
  them to no other.
  """
  def base, do: @base

  @doc "The reader wallet steps use: this module, or the site's test stand-in."
  def module, do: Application.get_env(:regents, :chain_client, __MODULE__)

  @doc "The transaction sent as `hash`, or `nil` while the chain does not know it."
  def transaction(chain, hash), do: request(chain, "eth_getTransactionByHash", [hash])

  @doc "The receipt for `hash`, or `nil` while it has not landed."
  def receipt(chain, hash), do: request(chain, "eth_getTransactionReceipt", [hash])

  defp request(%{chain_id: 8453}, method, params), do: Rpc.answer(method, params, @rpc_opts)
end
