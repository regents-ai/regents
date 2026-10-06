defmodule Regents.ChainClient do
  @moduledoc """
  Reads at the latest block for a sent wallet step, on Base or Ethereum.

  `RegentChain.Outcome` reads sent steps through `transaction/2` and `receipt/2`;
  Regent Credits also reads the newest block number to count Ethereum purchases.
  Every read is at `latest`: never wait for `safe` or `finalized`. Regents reads
  each chain through its own read endpoint (`:base_read_rpc_url`,
  `:ethereum_read_rpc_url`); the review's `rpc_url` is the public one the wallet
  is given, never a keyed server endpoint.
  """

  alias Regents.WalletActions.Rpc

  @callback transaction(RegentChain.Review.chain(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback receipt(RegentChain.Review.chain(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}

  @behaviour RegentCredits.ChainClient

  @rpc_opts [log_scope: "wallet steps"]
  @base %{chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"}

  @doc "Base, as a wallet is asked to switch to it."
  def base, do: @base

  @doc "The reader wallet steps use: this module, or the site's test stand-in."
  def module, do: Application.get_env(:regents, :chain_client, __MODULE__)

  @doc "The transaction sent as `hash`, or `nil` while the chain does not know it."
  @impl RegentCredits.ChainClient
  def transaction(chain, hash), do: request(chain, "eth_getTransactionByHash", [hash])

  @doc "The receipt for `hash`, or `nil` while it has not landed."
  @impl RegentCredits.ChainClient
  def receipt(chain, hash), do: request(chain, "eth_getTransactionReceipt", [hash])

  @doc "The newest block number."
  @impl RegentCredits.ChainClient
  def block_number(chain) do
    with {:ok, "0x" <> hex} <- request(chain, "eth_blockNumber", []) do
      {:ok, String.to_integer(hex, 16)}
    end
  end

  @doc """
  One JSON-RPC read on Base or Ethereum through the site's own endpoint. Without
  an Ethereum endpoint configured, nothing on Ethereum is read.
  """
  def request(%{chain_id: 8453}, method, params), do: Rpc.request(method, params, @rpc_opts)

  def request(%{chain_id: 1}, method, params) do
    case Application.get_env(:regents, :ethereum_read_rpc_url) do
      nil -> {:error, :chain_unavailable}
      url -> Rpc.request(method, params, [url: url] ++ @rpc_opts)
    end
  end
end
